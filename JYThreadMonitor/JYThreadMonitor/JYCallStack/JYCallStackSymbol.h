//
//  JYCallStackSymbol.h
//  test
//
//  Created by karthrine on 2022/1/12.
//

#import <Foundation/Foundation.h>
#include <stdio.h>
#include <stdint.h>


typedef struct{
    uint64_t address; // 基础地址
    uint64_t offset;  // 偏移地址
    const char * symbol; // 符号
    const char * machOName; // 对应的二进制Macho名字
} JYFuncInfo;


typedef struct{
    JYFuncInfo *stacks;
    int allocLenght;
    int length;
} JYCallStackInfo;


@interface JYCallStackSymbol : NSObject

void callStackOfSymbol(uintptr_t *backtraceBuffer, int length ,JYCallStackInfo *csInfo);

@end


