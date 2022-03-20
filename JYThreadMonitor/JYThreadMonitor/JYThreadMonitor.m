//
//  JYThreadMonitor.m
//  test
//
//  Created by karthrine on 2021/12/30.
//

#import "JYThreadMonitor.h"
#include <pthread/introspection.h>
#include <mach/mach.h>
#import "JYCallStack.h"


static pthread_introspection_hook_t original_pthread_introspection_hook_t = NULL;

/// 创建信号量
static dispatch_semaphore_t semaphore;

/// 线程总数
static int threadCount = 0;

/// 是否开启监控
static bool isMonitor = false;

/// 线程总数阈值
static int averageThreadCount = 40;

/// 线程在一定时间内新增数
static int newThreadCount = 0;

/// 线程在一定时间内新增阈值
static int newAverageThreadCount = 10;

@implementation JYThreadMonitor

/// 开启监控
+ (void)startMonitor{
    // 创建信号量 最大并发数为1
    semaphore = dispatch_semaphore_create(1);
    // 等待
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    mach_msg_type_number_t count;
    thread_act_array_t threads;
    // 获取到count
    task_threads(mach_task_self(), &threads, &count);
   
    // 保证加锁的时候，线程数量不变
    threadCount = count;
    
    // 添加🪝钩子函数
    original_pthread_introspection_hook_t = pthread_introspection_hook_install(jy_pthread_introspection_hook_t);
    
    // 解锁 信号量+1
    dispatch_semaphore_signal(semaphore);
    
    // 开始监控
    isMonitor = true;
    
    
    // 开启一个定时器 检测每秒线程创建 然后通过clearNewThreadCount置位0
    const char *queenIdentifier = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
    if (queenIdentifier == dispatch_queue_get_label(dispatch_get_main_queue())) {
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(clearNewThreadCount) userInfo:nil repeats:YES];
    }else{
        dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(clearNewThreadCount) userInfo:nil repeats:YES];
        });
    }
    printf("\n🔥💥💥💥💥💥 开启成功 当前有 %d 条线程💥💥💥💥💥🔥\n", threadCount);
}

// 当前线程总数
+ (int)currentThreadCount{
    return threadCount;
}


void jy_pthread_introspection_hook_t(unsigned int event,
                                      pthread_t thread, void *addr, size_t size){
    
    // 原来的正常调用
    if (original_pthread_introspection_hook_t) {
        original_pthread_introspection_hook_t(event,thread,addr,size);
    }
    
    // 如果是创建线程,则线程的数量+1，新增数+1
    if (event == PTHREAD_INTROSPECTION_THREAD_CREATE) {
        threadCount +=1;
        if (isMonitor && threadCount > averageThreadCount) {
            // 总数 超过阈值 警告或者记录堆栈
            jy_Log_CallStack(false, 0);
        }
        
        newThreadCount +=1;
        if (isMonitor && newThreadCount > newAverageThreadCount) {
            // 新增数 超过阈值 警告或者记录堆栈
            jy_Log_CallStack(true, newThreadCount);
        }
    }
    
    // 销毁线程，则线程数量-1，新增数-1
    if (event == PTHREAD_INTROSPECTION_THREAD_DESTROY) {
        threadCount -=1;
       
        if (newThreadCount > 0 ) {
            newThreadCount -=1;
        }
    }
}


void jy_Log_CallStack(bool isIncreaseLog, int num)
{
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (isIncreaseLog) {
        printf("\n🔥💥💥💥💥💥一秒钟开启 %d 条线程！💥💥💥💥💥🔥\n", num);
    }
    
    // 可以记录堆栈信息
    [JYCallStack callStackWithThread:JYCallStackTypeAllThread];
    
    dispatch_semaphore_signal(semaphore);
}


+ (void)clearNewThreadCount{
    newThreadCount = 0;
}

 


@end
