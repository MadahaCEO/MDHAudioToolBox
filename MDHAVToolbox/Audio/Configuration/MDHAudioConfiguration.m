//
//  MDHAudioConfiguration.m
//  MDHAVToolbox
//
//  Created by Apple on 2018/9/14.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import "MDHAudioConfiguration.h"


@interface MDHAudioConfiguration ()

@property (nonatomic, copy) NSString *audioName;

@end


@implementation MDHAudioConfiguration


+ (instancetype)defaultConfiguration {
    
    return [[MDHAudioConfiguration alloc] init];
}


- (instancetype)init {
    if (self = [super init]) {

        _bitRate    = MDHAudioBitRate_Default;
        _sampleRate = MDHAudioSampleRate_Default;
        _channel    = MDHAudioChannel_Default;
        _quality    = MDHAudioQuality_Default;
        _format     = MDHAudioFormat_Default;
        
        _audioName  = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];

    }
    return self;
}

- (void)dealloc {

    
}



#pragma mark - getter

- (NSString *)audioDirectoryPath {
    
    NSString *directoryPath = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    directoryPath = [directoryPath stringByAppendingPathComponent:@"audioDirectory"];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:directoryPath])
    {
        [fileManager createDirectoryAtPath:directoryPath
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:NULL];
    }
    
    return directoryPath;
}

- (NSString *)cafFilePath {
    
    NSString *fullName  = [NSString stringWithFormat:@"%@.%@",_audioName,(self.format == MDHAudioFormat_WAV) ? @"wav" : @"caf"];
    NSString *fullPath  = [self.audioDirectoryPath stringByAppendingPathComponent:fullName];
    
    return fullPath;
}

- (NSString *)mp3FilePath {
    
    NSString *fullName  = [NSString stringWithFormat:@"%@.mp3",_audioName];
    NSString *fullPath  = [self.audioDirectoryPath stringByAppendingPathComponent:fullName];

    return fullPath;
}


@end
