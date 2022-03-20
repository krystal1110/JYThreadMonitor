//
//  JYThreadMonitor.h
//  test
//
//  Created by karthrine on 2021/12/30.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JYThreadMonitor : NSObject


/// 开启监控
+ (void)startMonitor;

// 当前线程总数
+ (int)currentThreadCount;


@end

NS_ASSUME_NONNULL_END
