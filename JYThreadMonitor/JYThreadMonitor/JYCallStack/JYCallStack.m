//
//  KryCallStack.m
//  test
//
//  Created by karthrine on 2022/1/12.
//

#import "JYCallStack.h"
#import "JYCallStackSymbol.h"
#import <mach/mach.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/types.h>
#include <limits.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>

#pragma -mark DEFINE MACRO FOR DIFFERENT CPU ARCHITECTURE
#if defined(__arm64__)
#define DETAG_INSTRUCTION_ADDRESS(A) ((A) & ~(3UL))
#define JY_THREAD_STATE_COUNT ARM_THREAD_STATE64_COUNT
#define JY_THREAD_STATE ARM_THREAD_STATE64
#define JY_FRAME_POINTER __fp
#define JY_STACK_POINTER __sp
#define JY_INSTRUCTION_ADDRESS __pc

#elif defined(__arm__)
#define DETAG_INSTRUCTION_ADDRESS(A) ((A) & ~(1UL))
#define JY_THREAD_STATE_COUNT ARM_THREAD_STATE_COUNT
#define JY_THREAD_STATE ARM_THREAD_STATE
#define JY_FRAME_POINTER __r[7]
#define JY_STACK_POINTER __sp
#define JY_INSTRUCTION_ADDRESS __pc

#elif defined(__x86_64__)
#define DETAG_INSTRUCTION_ADDRESS(A) (A)
#define JY_THREAD_STATE_COUNT x86_THREAD_STATE64_COUNT
#define JY_THREAD_STATE x86_THREAD_STATE64
#define JY_FRAME_POINTER __rbp
#define JY_STACK_POINTER __rsp
#define JY_INSTRUCTION_ADDRESS __rip

#elif defined(__i386__)
#define DETAG_INSTRUCTION_ADDRESS(A) (A)
#define JY_THREAD_STATE_COUNT x86_THREAD_STATE32_COUNT
#define JY_THREAD_STATE x86_THREAD_STATE32
#define JY_FRAME_POINTER __ebp
#define JY_STACK_POINTER __esp
#define JY_INSTRUCTION_ADDRESS __eip

#endif

//栈帧模型
typedef struct {
    const uintptr_t *fp; //stp fp, lr, ...
    const uintptr_t lr;; // 返回地址
} JYStackFrame;

 

static thread_t _main_thread;

static int StackMaxDepth = 32;

@implementation JYCallStack

+(void)load{
    // 用于记录主线程
    _main_thread = mach_thread_self();
}


+ (NSString*)callStackWithThread:(JYCallStackType)type{
    
    NSString * callStackResult;
    if (type == JYCallStackTypeAllThread) {
        // 全部线程
        mach_msg_type_number_t count;
        thread_act_array_t threads;
        // 获取到thread
        if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS){
            return @"Unable to get all threads";
        }
        
        printf("线程数量为 %d",count);
        
        // 循环拿到线程thread_t
        NSMutableString *strM = [NSMutableString string];
        for (int i = 0; i< count; i++) {
            [strM appendString:[self backtraceOfThread:threads[i]]];
        }
        callStackResult = strM;
    
    }else if (type == JYCallStackTypeMainThread){
        // 主线程
        const char *queenIdentifier = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
        if (queenIdentifier == dispatch_queue_get_label(dispatch_get_main_queue())) {
            // 主线程 - 查看主线程
            callStackResult =  [self backtraceOfCurrentThread];
        }else{
            // 子线程 - 查看主线程
            callStackResult = [self backtraceOfThread:_main_thread];
        }
    }else if (type == JYCallStackTypeCurrentThread){
        // 当前线程
        callStackResult =  [self backtraceOfCurrentThread];
    }
    
    
    printf("\n⚠️⚠️⚠️⚠️⚠️⚠️👇堆栈👇⚠️⚠️⚠️⚠️⚠️⚠️\n");
    NSLog(@"\n%@", callStackResult);
    printf("⚠️⚠️⚠️⚠️⚠️⚠️👆堆栈👆⚠️⚠️⚠️⚠️⚠️⚠️\n\n");
    
    return callStackResult;
}

// 当前线程堆栈
+ (NSString*)backtraceOfCurrentThread{
    NSArray *arr = [NSThread callStackSymbols];
    NSMutableString *strM = [NSMutableString stringWithFormat:@"\n 当前线程为 callStack of thread: %@\n", [NSThread isMainThread]?@"main thread":[NSThread currentThread].name];
    for (NSString *symbol in arr) {
        [strM appendFormat:@"%@\n", symbol];
    }
    return strM.copy;
    
}


// 根据函数调用栈原理 递归拿到函数堆栈 然后恢复符号
+ (NSString*)backtraceOfThread:(thread_t)thread{
    
    NSMutableString *resultString = [[NSMutableString alloc] initWithFormat:@"Backtrace of Thread %u:\n", thread];
//    NSString * resultString;
    
    // 获取当前线程的上下文信息
    _STRUCT_MCONTEXT machineContext;
    if (!fillThradStateContext(thread, &machineContext)) {
        return [NSString stringWithFormat:@"Fail to get information about thread: %u",thread];
    }
    
    // pc寄存器
    const uintptr_t pcRegister = machineContext.__ss.JY_INSTRUCTION_ADDRESS;
    if (pcRegister == 0) {
        return @"Fail to get pc address";
    }
    
    
    // LR寄存器,函数返回地址.用于递归符号化堆栈
    uintptr_t lrRegister;
#if defined(__i386__) || defined(__x86_64__)
    lrRegister =  0;
#else
    lrRegister =  machineContext.__ss.__lr;
#endif
    
    // 结构体初始化
   
    // 拿到FP栈帧指针，指向函数的起始地址， *FP保存上一个函数的起始地址，就可以用于递归拿到函数栈
    const uintptr_t fpRegister = machineContext.__ss.JY_FRAME_POINTER;
    
//    if (framePtr == 0 || jy_mach_copyMem((void*)framePtr, &frame, sizeof(frame)) != KERN_SUCCESS){
//        return @"Fail to get fram address";
//    }
    
    // 初始化一个长度为StackMaxDepth的buffer
    uintptr_t backtraceBuffer[StackMaxDepth];
    int i = 0;
    // 首先把pc寄存器放进去，知道当前地址在哪
    backtraceBuffer[i++] = pcRegister;
    
    // 接着开始初始化结构体 构建栈帧
    JYStackFrame frame = {(void *)fpRegister, lrRegister};
    
    vm_size_t len = sizeof(frame);
    
    while (frame.fp && i < StackMaxDepth) {
        backtraceBuffer[i++] = frame.lr;
        bool flag = readFPMemory(frame.fp, &frame, len);
        if (!flag || frame.fp==0 || frame.lr==0) {
            break;
        }
    }
  
    // 收集好所有的lr 开始恢复符号表
    resultString = restoreSymbol(backtraceBuffer,i,thread).copy;
    
    return resultString;
}


//  通过thread初始化machineContext,里面有__ss, __ss里面有LR、FP、SP等寄存器.
bool fillThradStateContext(thread_t thread, _STRUCT_MCONTEXT *machineContext){
    mach_msg_type_number_t state_count = JY_THREAD_STATE_COUNT;
    kern_return_t kr = thread_get_state(thread, JY_THREAD_STATE, (thread_state_t)&machineContext->__ss, &state_count);
    return (kr == KERN_SUCCESS);
}


/// 拷贝FP到结构体
/// @param src FP
/// @param dst BSStackFrameEntry
/// @param numBytes BSStackFrameEntry长度
kern_return_t jy_mach_copyMem(const void *const src, void *const dst, const size_t numBytes){
    vm_size_t bytesCopied = 0;
    return vm_read_overwrite(mach_task_self(), (vm_address_t)src, (vm_size_t)numBytes, (vm_address_t)dst, &bytesCopied);
}


// 读取fp开始，len(16)字节长度的内存。因为stp fp, lr... ， fp占8字节，然后紧接着上面8字节是lr
bool readFPMemory(const void *fp, const void *dst, const vm_size_t len)
{
    vm_size_t bytesCopied = 0;
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)fp, len, (vm_address_t)dst, &bytesCopied);
    return KERN_SUCCESS == kr;
}


//还原符号表
NSString * restoreSymbol(uintptr_t *backtraceBuffer, int length ,thread_t thread){
    
    JYCallStackInfo * csInfo = malloc(sizeof(JYCallStackInfo));
    if (csInfo == NULL) {
        return @"fail to malloc";
    }
    csInfo->length = 0;
    csInfo->allocLenght = length;
    csInfo->stacks =  (JYFuncInfo *)malloc(sizeof(JYFuncInfo) * csInfo ->allocLenght);
    if (csInfo->stacks == NULL) {
        return @"error";
    }
    callStackOfSymbol(backtraceBuffer, length, csInfo);
    NSMutableString *strM = [NSMutableString stringWithFormat:@"\n 🔥🔥🔥JYCallStack of thread: %u 🔥🔥🔥\n", thread];
    for (int j = 0; j < csInfo->length; j++) {
        [strM appendFormat:@"%@", formatFuncInfo(csInfo->stacks[j])];
    }
    freeMemory(csInfo);
    return strM.copy;
}

NSString *formatFuncInfo(JYFuncInfo info)
{
    if (info.symbol == NULL) {
        return @"";
    }
    char *lastPath = strrchr(info.machOName, '/');
    NSString *fname = @"";
    if (lastPath == NULL) {
        fname = [NSString stringWithFormat:@"%-30s", info.machOName];
    }
    else
    {
        fname = [NSString stringWithFormat:@"%-30s", lastPath+1];
    }
    return [NSString stringWithFormat:@"%@ 0x%08" PRIxPTR " %s  +  %llu\n", fname, (uintptr_t)info.address, info.symbol, info.offset];
}

void freeMemory(JYCallStackInfo *csInfo)
{
    if (csInfo->stacks) {
        free(csInfo->stacks);
    }
    if (csInfo) {
        free(csInfo);
    }
}



@end
