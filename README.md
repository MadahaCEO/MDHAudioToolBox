# MDHAudioToolBox

  
  MDHAudioConfiguration *config = [MDHAudioConfiguration defaultConfiguration];
  config.format = MDHAudioFormat_MP3;
  NSError *error = nil;
  MDHAudioRecorder *recorder = [[MDHAudioRecorder alloc] initWithConfiguration:config error:&error];

[recorder start:^(NSString *filePath, NSString *duration, NSString *fileSize, NSError *error) {

NSLog(@"%@------%@------%@------%@",filePath,duration,fileSize,error.localizedDescription);
}];
