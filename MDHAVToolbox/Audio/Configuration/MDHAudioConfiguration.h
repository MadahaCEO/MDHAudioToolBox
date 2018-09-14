//
//  MDHAudioConfiguration.h
//  MDHAVToolbox
//
//  Created by Apple on 2018/9/14.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import <Foundation/Foundation.h>


/// 音频码率 (默认96Kbps)
typedef NS_ENUM (NSUInteger, MDHAudioBitRate) {
    
    /// 32Kbps 音频码率
    MDHAudioBitRate_8Kbps = 8,
    /// 64Kbps 音频码率
    MDHAudioBitRate_16Kbps = 16,
    /// 96Kbps 音频码率
    MDHAudioBitRate_24Kbps = 24,
    /// 128Kbps 音频码率
    MDHAudioBitRate_32Kbps = 32,
    /// 默认音频码率，默认为 96Kbps
    MDHAudioBitRate_Default = MDHAudioBitRate_16Kbps

    /*
    /// 32Kbps 音频码率
    MDHAudioBitRate_32Kbps = 32000,
    /// 64Kbps 音频码率
    MDHAudioBitRate_64Kbps = 64000,
    /// 96Kbps 音频码率
    MDHAudioBitRate_96Kbps = 96000,
    /// 128Kbps 音频码率
    MDHAudioBitRate_128Kbps = 128000,
    /// 默认音频码率，默认为 96Kbps
    MDHAudioBitRate_Default = MDHAudioBitRate_96Kbps
     */
};

/// 音频采样率 (默认44.1KHz)
typedef NS_ENUM (NSUInteger, MDHAudioSampleRate){
    /// 16KHz 采样率
    MDHAudioSampleRate_16000Hz = 16000,
    /// 44.1KHz 采样率
    MDHAudioSampleRate_44100Hz = 44100,
    /// 48KHz 采样率
    MDHAudioSampleRate_48000Hz = 48000,
    /// 默认音频采样率，默认为 44.1KHz
    MDHAudioSampleRate_Default = MDHAudioSampleRate_44100Hz
};

/// 通道数
typedef NS_ENUM(NSUInteger, MDHAudioChannel){
    /// 单通道
    MDHAudioChannel_1 = 1,
    /// 双通道
    MDHAudioChannel_2 = 2,
    /// 默认通道
    MDHAudioChannel_Default = MDHAudioChannel_1
};

///  Audio Live quality（音频质量）
typedef NS_ENUM (NSUInteger, MDHAudioQuality){
    /// 低音频质量
    MDHAudioQuality_Low = 7,
    /// 中音频质量
    MDHAudioQuality_Medium = 5,
    /// 高音频质量
    MDHAudioQuality_High = 2,
    /// 默认音频质量
    MDHAudioQuality_Default = MDHAudioQuality_High
};

/// 音频格式
typedef NS_ENUM(NSInteger, MDHAudioFormat) {
    MDHAudioFormat_CAF,
    MDHAudioFormat_WAV,
    MDHAudioFormat_MP3,
    MDHAudioFormat_Default = MDHAudioFormat_CAF
};

@interface MDHAudioConfiguration : NSObject

// 采样精度，采样位数
@property (nonatomic, assign) MDHAudioBitRate bitRate;
// 采样率
@property (nonatomic, assign) MDHAudioSampleRate sampleRate;
// 通道数
@property (nonatomic, assign) MDHAudioChannel channel;
// 音频质量
@property (nonatomic, assign) MDHAudioQuality quality;
// 音频格式
@property (nonatomic, assign) MDHAudioFormat  format;
// 存放所有录音文件的文件夹路径
@property (nonatomic, copy, readonly) NSString *audioDirectoryPath;
// caf文件路径
@property (nonatomic, copy, readonly) NSString *cafFilePath;
// mp3文件路径
@property (nonatomic, copy, readonly) NSString *mp3FilePath;


+ (instancetype)defaultConfiguration;

@end
