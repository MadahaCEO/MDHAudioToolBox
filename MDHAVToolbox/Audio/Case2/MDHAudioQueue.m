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
         从上至下是一个包含关系：每秒有SampleRate次采样，每次采样一个frame,每个frame有mChannelsPerFrame个样本，每个样本有mBitsPerChannel这么多数据。所以其他的数据大小都可以用以上这些来计算得到。当然前提是数据时没有编码压缩的
         */
        
        // 录制音频数据格式
        _streamDescription.mFormatID = kAudioFormatLinearPCM;
        // 标签格式
        _streamDescription.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
        // 语音每采样点占用位数[8/16/24/32]
        _streamDescription.mBitsPerChannel = _audioConfiguration.bitRate;
        // 单通道双通道
        _streamDescription.mChannelsPerFrame = _audioConfiguration.channel;
        // 每个数据包中的Bytes数量 &  每帧的Byte数
        _streamDescription.mBytesPerPacket = _streamDescription.mBytesPerFrame = (_streamDescription.mBitsPerChannel / 8) * _streamDescription.mChannelsPerFrame;
        // 每个数据包中的帧数量
        _streamDescription.mFramesPerPacket = 1;
        // 录音采样率(每秒钟采样的次数)
        _streamDescription.mSampleRate = _audioConfiguration.sampleRate;

        
        AudioQueueNewInput(&_streamDescription,
                           MCAudioQueueInuputCallback,
                           (__bridge void*)(self),
                           NULL,
                           NULL,
                           0,
                           &_audioQueue);
        
        AudioQueueAddPropertyListener(_audioQueue,
                                      kAudioQueueProperty_IsRunning,
                                      MCAudioInputQueuePropertyCallback,
                                      (__bridge void *)(self));

        for (int i = 0; i < kAudioQueueBufferCount; ++i)
        {
            AudioQueueBufferRef buffer;
            
            AudioQueueAllocateBuffer(_audioQueue, _bufferSize, &buffer);
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
    
    OSStatus status = AudioQueuePause(_audioQueue);
    if (status == noErr) {
        NSLog(@"error------pause");
    }
}

- (void)stop {
    
    OSStatus status = AudioQueueStop(_audioQueue, true);
    if (status == noErr) {
        NSLog(@"error------stop");
    }
}

- (void)cancel {
    
    OSStatus status = AudioQueueReset(_audioQueue);
    if (status == noErr) {
        NSLog(@"error------cancel");
    }
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
        
        
        
        
        //        NSData *mp3Data = [NSData dataWithBytes:&mp3Buffer length:encodedBytes];
        
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
