//
//  MDHAVToolbox.h
//  MDHAVToolbox
//
//  Created by Apple on 2018/8/18.
//  Copyright © 2018年 马大哈. All rights reserved.
//

#import <UIKit/UIKit.h>

//! Project version number for MDHAVToolbox.
FOUNDATION_EXPORT double MDHAVToolboxVersionNumber;

//! Project version string for MDHAVToolbox.
FOUNDATION_EXPORT const unsigned char MDHAVToolboxVersionString[];

// In this header, you should import all the public headers of your framework using statements like #import <MDHAVToolbox/PublicHeader.h>

/*

 引入lame 编译时很多警告
 Showing Recent Messages: Object file (/Users/apple/Desktop/项目/MDH/SDK/MDHAVToolbox/MDHAVToolbox/Audio/libmp3lame/libmp3lame.a(version.o)) was built for newer iOS version (11.2) than being linked (9.0)
 
 解决方法：在Build Settings -> other lingker Flags 中添加-w 就可以解决了
 */

#import <MDHAVToolbox/MDHAudioRecorder.h>

