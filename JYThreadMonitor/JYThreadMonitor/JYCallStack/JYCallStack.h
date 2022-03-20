//
//  JYCallStack.h
//  test
//
//  Created by karthrine on 2022/1/12.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, JYCallStackType) {
    JYCallStackTypeAllThread,     //全部线程
    JYCallStackTypeMainThread,    //主线程
    JYCallStackTypeCurrentThread  //当前线程
};

NS_ASSUME_NONNULL_BEGIN

@interface JYCallStack : NSObject


+ (NSString*)callStackWithThread:(JYCallStackType)type;
 


@end

NS_ASSUME_NONNULL_END
