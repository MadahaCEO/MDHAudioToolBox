//
//  MDHAudioQueue.m
//  MDHAVToolbox
//
//  Created by Apple on 2018/9/14.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import "MDHAudioQueue.h"
#import "lame.h"


static NSInteger kAudioQueueBufferCount = 3;


@interface MDHAudioQueue ()
{
    int read, write;
    FILE *pcm;
    FILE *mp3;
    
    lame_t lame;
    
    long curpos;
    
    AudioQueueRef _audioQueue;
    UInt32 _bufferSize;
    NSMutableData *_buffer;
    
    
}
@property(nonatomic, strong) MDHAudioConfiguration *audioConfiguration;
@property (nonatomic, assign, getter=isPausedByUser) BOOL pausedByUser;
@property (nonatomic, assign, getter=isNeedResumeOtherAudio) BOOL needResumeOtherAudio;
@property (nonatomic, assign) AudioStreamBasicDescription streamDescription;


@end


@implementation MDHAudioQueue


+ (AVAuthorizationStatus)isAuthorized {
    
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
}

+ (void)requestAccess:(void (^)(BOOL granted))handler {
    
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
        
        if (handler) {
            handler(granted);
        }
    }];
}


- (void)dealloc {
    
    NSLog(@"MDHAudioQueue----------dealloc");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}



- (instancetype)initWithConfiguration:(MDHAudioConfiguration *)configuration error:(NSError **)error {
    
    self = [super init];
    if (self) {
        
        _audioConfiguration = configuration;
        
        /**
         判断配置文件
         */
        if (error != NULL && !configuration) {
            *error = [NSError errorWithDomain:@"com.audioQueue.error"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey:@"音频配置文件不能为空"}];
            return nil;
        }
        
        
        /**
         切换回话类型
         */
        if (error != NULL &&![self switchCategory]) {
            *error = [NSError errorWithDomain:@"com.audioQueue.error"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey:@"session类型切换失败"}];
            return nil;
        }
        
        /*
         声音数据量的计算公式：数据量（字节 / 秒）=（采样频率（Hz）* 采样位数（bit）* 声道数）/ 8
         
         从上至下是一个包含关系：每秒有SampleRate次采样，每次采样一个frame,每个frame有mChannelsPerFrame个样本，每个样本有mBitsPerChannel这么多数据。所以其他的数据大小都可以用以上这些来计算得到。当然前提是数据时没有编码压缩的
         */
        
        /*
         录制音频数据格式 AAC、PCM
         */
        _streamDescription.mFormatID = kAudioFormatLinearPCM;
        /*
         每种格式特定的标志，无损编码 ，0表示没有
         标签格式
         */
        _streamDescription.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        /*
         记录每次采样值数值大小的位数。采样位数通常有8bits或16bits两种，采样位数越大，所能记录的声音变化度就越细腻，相应的数据量就越大。
         语音每采样点占用位数[8/16/24/32]
         */
        _streamDescription.mBitsPerChannel = _audioConfiguration.bitRate;
        /*
         处理的声音是单声道还是立体声。单声道在声音处理过程中只有单数据流，而立体声则需要左右声道的两个数据流。
         显然，立体声的效果要好，但相应数据量要比单声道数据量加倍。
         单通道双通道
         */
        _streamDescription.mChannelsPerFrame = _audioConfiguration.channel;
        // 每个数据包中的Bytes数量 &  每帧的Byte数
        _streamDescription.mBytesPerPacket = _streamDescription.mBytesPerFrame = (_streamDescription.mBitsPerChannel / 8) * _streamDescription.mChannelsPerFrame;
        // 每个数据包中的帧数量
        _streamDescription.mFramesPerPacket = 1;
        // 录音采样率(每秒钟采样的次数)
        _streamDescription.mSampleRate = _audioConfiguration.sampleRate;
        
        // 新建一个队列,第二个参数注册回调函数，第三个防止内存泄露
        
        /*
         新建一个音频队列
         param1. 音频格式
         param2. 回调函数
         param3. 防止内存泄露
         param4. 音频队列(设置成NULL，系统会默认按照内部线程异步执行录音)
         param5. runloopmodel
         param6. 以备将来使用的备用参数
         param7. 音频队列
         */
        AudioQueueNewInput(&_streamDescription,
                           MCAudioQueueInuputCallback,
                           (__bridge void*)(self),
                           NULL,
                           NULL,
                           0,
                           &_audioQueue);
        
        /*
         添加一个监听回调的属性
         param1. 音频队列
         param2. kAudioQueueProperty_IsRunning 标明队列是否正在运行的 UInt32 类型的只读属性值，
         当录音设备开始或停止就会发送通知，但是不是开始或停止就必须发送通知。
         param3. 当属性值改变就会调用的回调函数
         param4. 回调给监听函数的值
         */
        AudioQueueAddPropertyListener(_audioQueue,
                                      kAudioQueueProperty_IsRunning,
                                      MCAudioInputQueuePropertyCallback,
                                      (__bridge void *)(self));
        
        for (int i = 0; i < kAudioQueueBufferCount; ++i)
        {
            AudioQueueBufferRef buffer;
            /*
             注意：为每个缓冲区分配大小，可根据具体需求进行修改,但是一定要注意必须满足转换器的需求,
             转换器只有每次给1024帧数据才会完成一次转换,如果需求为采集数据量较少则用本例提供的pcm_buffer对数据进行累加后再处理
             */
            
            /*
             请求音频队列创建缓冲区
             param1. 申请创建缓冲区的音频队列
             param2. 缓冲区大小（单位：字节） 一个合适的缓冲区大小取决于你将执行数据处理以及音频数据格式。
             param3. 输出地址（指向创建的音频缓冲区）
             */
            AudioQueueAllocateBuffer(_audioQueue, _bufferSize, &buffer);
            
            /*
             在音频队列中分配一个缓冲区用于存储 录音数据 或 播放数据
             param1. 分配缓冲区的音频队列
             param2. 分配的缓冲区
             param3.
             param4.
             */
            AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
        }
        
        /**
         lame 准备
         */
        mp3 = fopen([_audioConfiguration.mp3FilePath  cStringUsingEncoding:NSASCIIStringEncoding], "wb+");
        
        lame = lame_init();
        lame_set_in_samplerate(lame, _audioConfiguration.sampleRate);
        lame_set_num_channels(lame, _audioConfiguration.channel);
        lame_set_VBR(lame, vbr_default);
        lame_set_brate(lame, _audioConfiguration.bitRate);
        lame_set_quality(lame,_audioConfiguration.quality);
        
        int result = lame_init_params(lame);
        if (result == -1 && error != NULL) {
            *error = [NSError errorWithDomain:@"com.audioQueue.error"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey:@"lame 初始化失败"}];
            return nil;
        }
        
        
        [self addInterruptionNotification];
        
    }
    return self;
}


- (BOOL)switchCategory {
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    /**
     这里 AVAudioSessionCategoryOptionDuckOthers , 所以录音完毕继续其他app播放音乐。（其他类型酌情而定）
     */
    self.needResumeOtherAudio = session.isOtherAudioPlaying;
    
    
    NSError *error = nil;
    /*
     AVAudioSessionCategoryPlayAndRecord: 录音同时《支持》其他音乐播放
     AVAudioSessionCategoryRecord       : 录音同时《停止》其他音乐播放
     
     AVAudioSessionCategoryOptionMixWithOthers:   录音同时《不处理》其他音乐声音
     AVAudioSessionCategoryOptionDuckOthers:      录音同时《压低》  其他音乐声音
     */
    [session setCategory: AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDuckOthers error:&error];
    if (error) {
        [session setActive:YES error:&error];
    }
    
    return error ? NO : YES;
}

- (void)start:(MDHAudioQueueComplete)block {
    
    self.completeBlock = block;
    self.pausedByUser = NO;
    
    /*
     开始录音 或 播放
     
     param2. inStartTime这个音频队列实例开始的时间。如果需要指定一个时间的话，要根据AudioTimeStamp创建一个结构。
     如果这个参数传NULL的话，表明这个audioQueue队列应该尽快开启。
     */
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    if (status == noErr) {
        NSLog(@"error------start");
    }
}

- (void)reStart {
    
    if (![self switchCategory] && self.completeBlock) {
        NSError *error = [NSError errorWithDomain:@"com.recorder.error"
                                             code:0
                                         userInfo:@{NSLocalizedDescriptionKey:@"session类型切换失败"}];
        self.completeBlock(nil, nil, nil, error);
        
        return;
    }
    
    self.pausedByUser = NO;
    
    OSStatus status = AudioQueueStart(_audioQueue, NULL);
    if (status == noErr) {
        NSLog(@"error------reStart");
    }
}

- (void)pause {
    
    self.pausedByUser = YES;
    
    /*
     暂停录音 或 播放
     
     对一个音频队列调用暂停，不会影响队列中已经有的buffers、也不会reset（重置）这个音频队列。
     如果要恢复播放或者录制，只需要调用：AudioQueueStart.
     */
    OSStatus status = AudioQueuePause(_audioQueue);
    if (status == noErr) {
        NSLog(@"error------pause");
    }
}

- (void)stop {
    
    /*
     重新设置解码器的解码状态 (类似lame_encode_flush)
     
     为了使所有进入audioQueue的数据都被处理，在最后一个音频缓冲进入音频队列后，
     调用这个函数可以使即将结束的audioQueue不会影响到后面的audioQueue。
     在AudioQueueStop之前调用AudioQueueFlush可以确保所有进入队列的数据都达到了目的地（意思是：被处理）。
     */
    OSStatus status =AudioQueueFlush(_audioQueue);
    if (status == noErr) {
        NSLog(@"error------AudioQueueFlush");
    }
    
    /*
     停止录音 或 播放
     param2. 是否马上停止，如果传true的话，stop马上进行，即，是同步进行的。
     如果传flase,则是异步进行的，函数先返回，但是音频队列直到，队列中所有的的数据被录制或者回放完成才真正结束。
     */
    OSStatus status = AudioQueueStop(_audioQueue, true);
    if (status == noErr) {
        NSLog(@"error------AudioQueueStop");
    }
}

- (void)cancel {
    
    OSStatus status = AudioQueueStop(_audioQueue, true);
    if (status == noErr) {
        NSLog(@"error------AudioQueueStop");
    }
    
    //    OSStatus status = AudioQueueReset(_audioQueue);
    //    if (status == noErr) {
    //        NSLog(@"error------cancel");
    //    }
}



#pragma mark - Notification

- (void)addInterruptionNotification {
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioSessionWasInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
    
}

- (void)audioSessionWasInterrupted:(NSNotification *)notification {
    
    if (AVAudioSessionInterruptionTypeBegan == [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue]) {
        NSLog(@"begin");
        
        if (!self.isPausedByUser) { // 是否已经被用户暂停了
            OSStatus status = AudioQueuePause(_audioQueue);
            if (status == noErr) {
                NSLog(@"error------pause");
            }
        }
    } else if (AVAudioSessionInterruptionTypeEnded == [notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue]) {
        NSLog(@"begin - end");
        
        /*
         如果之前处于录音状态，就可以继续录音
         如果之前已经暂停了，就不需要再录音
         */
        if (!self.isPausedByUser) {
            [self reStart];
        }
    }
}





/*!
 @typedef    AudioQueueInputCallback
 queue has finished filling a buffer.
 当一个录音的音频队列已经填满其中一个缓冲区会调用回调函数
 @param      inUserData
 为录音数据创建一个新的音频队列(AudioQueueNewInput)中的标明的参数
 @param      inAQ
 音频队列调用回调函数
 @param      inBuffer
 音频队列中最新被填充满的最新的音频数据缓冲区
 @param      inStartTime
 
 @param      inNumberPacketDescriptions
 多少个数据包
 @param      inPacketDescs
 音频流数据包描述
 */
static void MCAudioQueueInuputCallback(void *inClientData,
                                       AudioQueueRef inAQ,
                                       AudioQueueBufferRef inBuffer,
                                       const AudioTimeStamp *inStartTime,
                                       UInt32 inNumberPacketDescriptions,
                                       const AudioStreamPacketDescription *inPacketDescs)
{
    /**/
    MDHAudioQueue *audioOutputQueue = (__bridge MDHAudioQueue *)inClientData;
    [audioOutputQueue handleAudioQueueOutputCallBack:inAQ
                                              buffer:inBuffer
                                         inStartTime:inStartTime
                          inNumberPacketDescriptions:inNumberPacketDescriptions
                                       inPacketDescs:inPacketDescs];
}

- (void)handleAudioQueueOutputCallBack:(AudioQueueRef)audioQueue
                                buffer:(AudioQueueBufferRef)buffer
                           inStartTime:(const AudioTimeStamp *)inStartTime
            inNumberPacketDescriptions:(UInt32)inNumberPacketDescriptions
                         inPacketDescs:(const AudioStreamPacketDescription *)inPacketDescs
{
    //    if (_started)
    //    {
    
    /*
     
     typedef void (*AudioQueueInputCallback)(
     void * __nullable               inUserData,
     AudioQueueRef                   inAQ,
     AudioQueueBufferRef             inBuffer,
     const AudioTimeStamp *          inStartTime,
     UInt32                          inNumberPacketDescriptions,
     const AudioStreamPacketDescription * __nullable inPacketDescs);
     */
    
    int mp3DataSize = inNumberPacketDescriptions;
    unsigned char mp3Buffer[mp3DataSize];
    
    int encodedBytes = 0;
    
    
    /* AudioQueueBuffer 结构体
     typedef AudioQueueBuffer *AudioQueueBufferRef;
     
     mAudioData: 这是一个指向音频数据缓冲区的指针
     inNumberPacketDescriptions: 数据包
     */
    if (_audioConfiguration.channel == 1) {
        // 单通道
        encodedBytes = lame_encode_buffer( lame, buffer->mAudioData,NULL, inNumberPacketDescriptions, mp3Buffer, mp3DataSize);
        
    } else {
        
        // 双通道
        encodedBytes = lame_encode_buffer_interleaved(lame, buffer->mAudioData, inNumberPacketDescriptions, mp3Buffer, mp3DataSize);
    }
    
    fwrite(mp3Buffer, encodedBytes, 1, mp3);
    
    [_buffer appendBytes:buffer->mAudioData length:buffer->mAudioDataByteSize];
    
    if ([_buffer length] >= _bufferSize)
    {
        NSRange range = NSMakeRange(0, _bufferSize);
        NSData *subData = [_buffer subdataWithRange:range];
        //            [_delegate inputQueue:self inputData:subData numberOfPackets:inNumberPacketDescriptions];
        [_buffer replaceBytesInRange:range withBytes:NULL length:0];
    }
    
    AudioQueueEnqueueBuffer(_audioQueue, buffer, 0, NULL);
    
    /* */
    
    //    }
}


static void MCAudioInputQueuePropertyCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    //    __unsafe_unretained MCAudioInputQueue *audioQueue = (__bridge MCAudioInputQueue *)inUserData;
    //    [audioQueue handleAudioQueuePropertyCallBack:inAQ property:inID];
}
- (void)handleAudioQueuePropertyCallBack:(AudioQueueRef)audioQueue property:(AudioQueuePropertyID)property
{
    if (property == kAudioQueueProperty_IsRunning)
    {
        UInt32 isRunning = 0;
        UInt32 size = sizeof(isRunning);
        AudioQueueGetProperty(audioQueue, property, &isRunning, &size);
        //        _isRunning = isRunning;
    }
}

@end

