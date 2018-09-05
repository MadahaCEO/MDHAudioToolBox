//
//  MDHAudioRecorder.h
//  MDHAVFoudation
//
//  Created by Apple on 2018/8/8.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>


/*
 @enum MDHAudioFormat values
 @abstract   音频格式
 @discussion
 
 @constant   MDHAudioFormatCAF    xxx.caf
 @constant   MDHAudioFormatWAV    xxx.wav
 @constant   MDHAudioFormatMP3    xxx.mp3
*/
typedef NS_ENUM(NSInteger, MDHAudioFormat) {
    MDHAudioFormatCAF,
    MDHAudioFormatWAV,
    MDHAudioFormatMP3
};


/**
 @abstract   录音回调
 
 @param filePath    录音文件路径（相对路径）
 @param duration    时长
 @param fileSize    文件大小（kb）
 @param error       录音或转码是否异常
 */
typedef void(^MDHAudioRecorderCompleteBlock)(NSString *filePath, NSString *duration, NSString *fileSize, NSError *error);

@interface MDHAudioRecorder : NSObject

@property(nonatomic, copy) MDHAudioRecorderCompleteBlock completeBlock;


/**
 @abstract   判断授权状态
 
 AVAuthorizationStatusNotDetermined   没有询问是否开启麦克风
 AVAuthorizationStatusRestricted      未授权，家长限制
 AVAuthorizationStatusDenied          已经拒绝授权
 AVAuthorizationStatusAuthorized      已经授权过
 */
+ (AVAuthorizationStatus)isAuthorized;

/**
 @abstract  请求系统授权
  */
+ (void)requestAccess:(void (^)(BOOL granted))handler;



/**
 @abstract   初始化

 @param bitRate     比特率（8、16、24、32）
        caf、wav音频格式比特率支持
        mp3音频格式都支持，但是原始音频格式必须默认16（caf、wav），否则有可能转码失败。
 @param channnels   通道（1、2）
 @param sampleRate  采样率（8000、16000、44100）
 @param audioFormat 音频格式（枚举类型）
 @param error       参数错误

 */
- (instancetype)initWithBitRate:(int)bitRate
                      channnels:(int)channnels
                     sampleRate:(int)sampleRate
                    audioFormat:(MDHAudioFormat)audioFormat
                  recorderError:(NSError **)error;

/**
 @abstract   开始录音
 
 @param block  回调
 */
- (void)start:(MDHAudioRecorderCompleteBlock)block;

/**
 @abstract   继续录音
  */
- (void)reStart;

/**
 @abstract   暂停
 */
- (void)pause;

/**
 @abstract   停止\结束
 */
- (void)stop;

/**
 @abstract   取消
 */
- (void)cancel;

/**
 @abstract  删除音频文件
 */
+ (void)removeAudio:(NSString *)path;

@end
