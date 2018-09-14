//
//  MDHAudioRecorder.m
//  MDHAVFoudation
//
//  Created by Apple on 2018/8/8.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import "MDHAudioRecorder.h"
#import "MDHMP3Conversion.h"

@interface MDHAudioRecorder ()<AVAudioRecorderDelegate>

@property(nonatomic, strong) MDHAudioConfiguration *audioConfiguration;
@property (nonatomic, strong) AVAudioRecorder  *recorder;
@property (nonatomic, strong) MDHMP3Conversion *mp3Convert;
@property (nonatomic, assign, getter=isPausedByUser) BOOL pausedByUser;
@property (nonatomic, assign, getter=isNeedResumeOtherAudio) BOOL needResumeOtherAudio;


@end


@implementation MDHAudioRecorder

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
    
    NSLog(@"MDHAudioRecorder----------dealloc");
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
            *error = [NSError errorWithDomain:@"com.recorder.error"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey:@"音频配置文件不能为空"}];
            return nil;
        }
        
        
        /**
         切换回话类型
         */
        if (error != NULL &&![self switchCategory]) {
            *error = [NSError errorWithDomain:@"com.recorder.error"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey:@"session类型切换失败"}];
            return nil;
        }
        
        
        /**
         初始化录音器
         */
        NSDictionary *dic = @{
                              AVSampleRateKey        : @(_audioConfiguration.sampleRate),
                              AVFormatIDKey          : @(kAudioFormatLinearPCM),
                              AVLinearPCMBitDepthKey : @(_audioConfiguration.bitRate),
                              AVNumberOfChannelsKey  : @(_audioConfiguration.channel)
                              };
        
        NSURL *url = [NSURL URLWithString:_audioConfiguration.cafFilePath];
        
        NSError *recorderError = nil;
        _recorder = [[AVAudioRecorder alloc] initWithURL:url settings:dic error:&recorderError];
        if (error != NULL && recorderError) {
            *error = [NSError errorWithDomain:@"com.recorder.error"
                                         code:0
                                     userInfo:@{NSLocalizedDescriptionKey:@"AVAudioRecorder 初始化失败"}];
            return nil;
        }
        
        _recorder.delegate = self;
        [_recorder prepareToRecord];

        
        /**
         初始化MP3转换
         */
        if (configuration.format == MDHAudioFormat_MP3) {
        
            NSError *mp3Error = nil;
            _mp3Convert = [[MDHMP3Conversion alloc] initWithConfiguration:configuration error:&mp3Error];
            
            if (mp3Error && error != NULL) {
                *error = [NSError errorWithDomain:@"com.recorder.error"
                                             code:0
                                         userInfo:@{NSLocalizedDescriptionKey:@"lame 初始化失败"}];
                
                return nil;
            }
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

- (void)start:(MDHAudioRecorderCompleteBlock)block {
    
    self.completeBlock = block;
    
    self.pausedByUser = NO;

    [self.recorder record];

    if (_audioConfiguration.format == MDHAudioFormat_MP3) {
        [self convertToMP3];
    }
}

- (void)convertToMP3 {
    
    __weak typeof(self)weakSelf = self;
    [self.mp3Convert start:^(BOOL deleteFile) {
        __weak typeof(weakSelf)strongSelf = weakSelf;
        
        [[NSFileManager defaultManager] removeItemAtPath:_audioConfiguration.cafFilePath error:nil];

        if (deleteFile) {
            // 取消操作无需回调，直接删除文件。
            [[NSFileManager defaultManager] removeItemAtPath:_audioConfiguration.mp3FilePath error:nil];
            
        } else {
            
            NSString *tempPath = _audioConfiguration.mp3FilePath?:@"";
            
            AVURLAsset* audioAsset =[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:tempPath] options:nil];
            CMTime time = audioAsset.duration;
            NSString *duration = [NSString stringWithFormat:@"%.0f ms",CMTimeGetSeconds(time) * 1000];
            
            long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:tempPath error:nil].fileSize/1024;
            NSString *fileSize = [NSString stringWithFormat:@"%lld kb",size];
            
            if (strongSelf.completeBlock) {
                strongSelf.completeBlock(tempPath, duration, fileSize, nil);
            }
        }
    }];
}

- (void)reStart {
    
    if (![self switchCategory] && self.completeBlock) {
        NSError *error = [NSError errorWithDomain:@"com.recorder.error"
                                             code:0
                                         userInfo:@{NSLocalizedDescriptionKey:@"session类型切换失败"}];
        self.completeBlock(nil, nil, nil, error);
        
        return;
    }
    
    
    if (!self.recorder.isRecording) {
        
        self.pausedByUser = NO;

        [self.recorder record];
        
        if (_audioConfiguration.format == MDHAudioFormat_MP3) {
            [self.mp3Convert reStart];
        }
    }
}

- (void)pause {
    
    self.pausedByUser = YES;

    [self.recorder pause];
    
    if (_audioConfiguration.format == MDHAudioFormat_MP3) {
        [self.mp3Convert pause];
    }
}

- (void)stop {
    
    [self.recorder stop];
    
    if (_audioConfiguration.format == MDHAudioFormat_MP3) {
        [self.mp3Convert stop];
    }
}

- (void)cancel {
    
    [self.recorder stop];

    if (_audioConfiguration.format == MDHAudioFormat_MP3) {
        [self.mp3Convert cancel];
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
            
            [self.recorder pause];
            
            if (_audioConfiguration.format == MDHAudioFormat_MP3) {
                [self.mp3Convert pause];
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


#pragma mark - AVAudioRecorderDelegate
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    
    if (_audioConfiguration.format == MDHAudioFormat_MP3) {
        return;
    }
    
    NSString *tempPath = _audioConfiguration.cafFilePath?:@"";
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:tempPath]) {
        NSLog(@"111111");
    } else {
        NSLog(@"22222");

    }
    
    AVURLAsset* audioAsset =[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:tempPath] options:nil];
    CMTime time = audioAsset.duration;
    NSString *duration = [NSString stringWithFormat:@"%.0f ms",CMTimeGetSeconds(time) * 1000];
    
    long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:tempPath error:nil].fileSize/1024;
    NSString *fileSize = [NSString stringWithFormat:@"%lld kb",size];
    
    if (self.completeBlock) {
        self.completeBlock(tempPath, duration, fileSize, nil);
    }
}


@end
