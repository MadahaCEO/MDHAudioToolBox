//
//  MDHMP3Conversion.h
//  MDHAVFoudation
//
//  Created by Apple on 2018/8/7.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 @abstract   转码回调
 
 @param deleteFile   正常结束&取消操作
 */
typedef void(^MDHMP3CompleteBlock)(BOOL deleteFile, NSError *error);

@interface MDHMP3Conversion : NSObject

@property(nonatomic, copy) MDHMP3CompleteBlock completeBlock;


/**
 @abstract   初始化（MP3文件路径与传入的原始音频文件路径一致）
 
 @param fromPath    原始音频文件路径（例如: document/xxxx.caf）
 @param toPath      mp3文件路径    （例如: document/yyyy.mp3）
 @param bitRate     比特率（16）
 @param channnels   通道（1、2）
 @param sampleRate  采样率（8000、16000、44100）
 */

- (instancetype)initWithPath:(NSString *)fromPath
                      toPath:(NSString *)toPath
                     bitRate:(int)bitRate
                   channnels:(int)channnels
                  sampleRate:(int)sampleRate
                convertError:(NSError **)convertError;


/**
 @abstract   开始转码
 
 @param cBlock  回调
 */
- (void)start:(MDHMP3CompleteBlock)cBlock;

/**
 @abstract   继续转码
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

@end
