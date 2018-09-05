//
//  MDHAudioRecorder.m
//  MDHAVFoudation
//
//  Created by Apple on 2018/8/8.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import "MDHAudioRecorder.h"
#import "MDHMP3Conversion.h"

#import <MDHFoundation/MDHFoundation.h>

@interface MDHAudioRecorder ()<AVAudioRecorderDelegate>

@property (nonatomic, copy)   NSString *realAudioPath;
@property (nonatomic, copy)   NSString *realMP3Path;
@property (nonatomic, assign) int realBitRate;
@property (nonatomic, assign) int realChannels;
@property (nonatomic, assign) int realSampleRate;
@property (nonatomic, assign) MDHAudioFormat realFormat;

@property (nonatomic, strong) AVAudioRecorder  *recorder;
@property (nonatomic, strong) MDHMP3Conversion *mp3Convert;

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
    
    NSLog(@"----------");
}

- (instancetype)initWithBitRate:(int)bitRate
                      channnels:(int)channnels
                     sampleRate:(int)sampleRate
                    audioFormat:(MDHAudioFormat)audioFormat
                  recorderError:(NSError **)error {

    self = [super init];
    if (self) {
        
        self.realAudioPath    = [self pcmFilePath:audioFormat];
        self.realMP3Path      = [self mp3FilePath];
        self.realBitRate      = (audioFormat == MDHAudioFormatMP3) ? 16 : bitRate;
        self.realChannels     = channnels;
        self.realSampleRate   = sampleRate;
        self.realFormat       = audioFormat;

       
        NSArray *bitRateArray     = @[@(8),@(16),@(24),@(32)];
        NSArray *sampleRateArray  = @[@(8000),@(16000),@(44100)];
        NSArray *channnelsArray   = @[@(1),@(2)];
        NSArray *audioFormatArray = @[@(MDHAudioFormatCAF),@(MDHAudioFormatWAV),@(MDHAudioFormatMP3)];

        if (![bitRateArray containsObject:@(bitRate)] ||
            ![sampleRateArray containsObject:@(sampleRate)] ||
            ![channnelsArray containsObject:@(channnels)] ||
            ![audioFormatArray containsObject:@(audioFormat)]) {
            
            if (error != NULL) {//判断调用方是否需要获取错误信息
                *error = [NSError errorWithDomain:@"com.recorder.error"
                                             code:0
                                         userInfo:@{NSLocalizedDescriptionKey:@"参数异常"}];                
                return nil;
            }
        }
    }
    return self;
}


- (BOOL)switchCategory {
    
    BOOL valid = YES;
    
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord error:&error];
    if (error && self.completeBlock) {
        self.completeBlock(nil, nil, nil, error);
        valid = NO;
    }
    
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error && self.completeBlock) {
        self.completeBlock(nil, nil, nil, error);
        valid = NO;
    }
    
    return valid;
}

- (void)start:(MDHAudioRecorderCompleteBlock)block {
    
    self.completeBlock = block;

    if (![self switchCategory]) {
        return;
    }
    
    NSDictionary *dic = @{
                          AVSampleRateKey        : @(self.realSampleRate),
                          AVFormatIDKey          : @(kAudioFormatLinearPCM),
                          AVLinearPCMBitDepthKey : @(self.realBitRate),
                          AVNumberOfChannelsKey  : @(self.realChannels)
                          };
    
    NSURL *url = [NSURL URLWithString:self.realAudioPath];

    NSError *error = nil;
    self.recorder = [[AVAudioRecorder alloc] initWithURL:url settings:dic error:nil];
    if (error && self.completeBlock) {
        self.completeBlock(nil, nil, nil, error);
        return;
    }
    
    self.recorder.delegate = self;

    [self.recorder prepareToRecord];
    [self.recorder record];

    if (self.realFormat == MDHAudioFormatMP3) {
        [self convertToMP3];
    }
}

- (void)convertToMP3 {
    
    NSError *error = nil;
    self.mp3Convert = [[MDHMP3Conversion alloc] initWithPath:self.realAudioPath
                                                      toPath:self.realMP3Path
                                                     bitRate:self.realBitRate
                                                   channnels:self.realChannels
                                                  sampleRate:self.realSampleRate
                                                convertError:&error];
    if (error) {
        if (self.completeBlock) {
            self.completeBlock(nil, nil, nil, error);
        }
        return;
    }
    
    MDHWeakSelf(self);
    [self.mp3Convert start:^(BOOL deleteFile, NSError *error) {
        MDHStrongSelf(weakSelf);

        if (error) {
            if (strongSelf.completeBlock) {
                self.completeBlock(nil, nil, nil, error);
            }
        } else {
            
            if (deleteFile) {
                // 取消操作无需回调，直接删除文件。
                [[NSFileManager defaultManager] removeItemAtPath:strongSelf.realMP3Path error:nil];
                [[NSFileManager defaultManager] removeItemAtPath:strongSelf.realAudioPath error:nil];

            } else {
                
                NSString *tempPath = strongSelf.realMP3Path?:@"";
                NSString *lastPath = [tempPath stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@""];
                
                AVURLAsset* audioAsset =[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:tempPath] options:nil];
                CMTime time = audioAsset.duration;
                NSString *duration = [NSString stringWithFormat:@"%.0f",CMTimeGetSeconds(time) * 1000];
                
                long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:tempPath error:nil].fileSize/1024;
                NSString *fileSize = [NSString stringWithFormat:@"%lld kb",size];
                
                if (self.completeBlock) {
                    self.completeBlock(lastPath, duration, fileSize, nil);
                }
            }
        }
    }];
}

- (void)reStart {
    
    if (!self.recorder.isRecording) {
        [self.recorder record];
        
        if (self.realFormat == MDHAudioFormatMP3) {
            [self.mp3Convert reStart];
        }
    }
}

- (void)pause {
    
    [self.recorder pause];
    
    if (self.realFormat == MDHAudioFormatMP3) {
        [self.mp3Convert pause];
    }
}

- (void)stop {
    
    [self.recorder stop];
    
    if (self.realFormat == MDHAudioFormatMP3) {
        [self.mp3Convert stop];
    }
}

- (void)cancel {
    [self.recorder stop];

    if (self.realFormat == MDHAudioFormatMP3) {
        [self.mp3Convert cancel];
    }
}


+ (void)removeAudio:(NSString *)path {
    
    NSString *fullPath = [NSHomeDirectory() stringByAppendingPathComponent:path];

    if ([path.pathExtension.lowercaseString isEqualToString:@"mp3"]) {
        
        NSString *otherFullPath = [fullPath stringByReplacingOccurrencesOfString:@"mp3" withString:@"caf"];
        [[NSFileManager defaultManager] removeItemAtPath:otherFullPath error:nil];

    }
    
    [[NSFileManager defaultManager] removeItemAtPath:fullPath error:nil];
}


#pragma mark - File action

- (NSString *)pcmFilePath:(MDHAudioFormat)format {
    
    NSString *name = [NSString stringWithFormat:@"%@.%@",[NSDate timestamp],(format == MDHAudioFormatWAV) ? @"wav" : @"caf"];
    NSString *path = [MDHTempPath stringByAppendingPathComponent:name];
    
    NSLog(@"%@----------",path);

    return path;
}

- (NSString *)mp3FilePath {
    
    NSString *name = self.realAudioPath.lastPathComponent.stringByDeletingPathExtension;
    NSString *mp3  = [NSString stringWithFormat:@"%@.mp3",name];
    NSString *path = [MDHTempPath stringByAppendingPathComponent:mp3];
    return path;
}


#pragma mark - AVAudioRecorderDelegate
- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    
    if (self.realFormat == MDHAudioFormatMP3) {
        return;
    }
    
    NSString *tempPath = self.realAudioPath?:@"";
    NSString *lastPath = [tempPath stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@""];
    
    AVURLAsset* audioAsset =[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:tempPath] options:nil];
    CMTime time = audioAsset.duration;
    NSString *duration = [NSString stringWithFormat:@"%.0f",CMTimeGetSeconds(time) * 1000];
    
    long long size = [[NSFileManager defaultManager] attributesOfItemAtPath:tempPath error:nil].fileSize/1024;
    NSString *fileSize = [NSString stringWithFormat:@"%lld kb",size];
    
    if (self.completeBlock) {
        self.completeBlock(lastPath, duration, fileSize, nil);
    }
    
    [[AVAudioSession sharedInstance] setActive:YES withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError * __nullable)error {
    [self cancel];
}

- (void)audioRecorderBeginInterruption:(AVAudioRecorder *)recorder {
    [self pause];
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder withOptions:(NSUInteger)flags {
    [self reStart];
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder withFlags:(NSUInteger)flags {
    [self reStart];
}

- (void)audioRecorderEndInterruption:(AVAudioRecorder *)recorder {
    [self reStart];
}


@end
