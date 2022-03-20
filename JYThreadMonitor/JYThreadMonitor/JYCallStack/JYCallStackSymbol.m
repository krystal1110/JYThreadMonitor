//
//  JYCallStackSymbol.m
//  test
//
//  Created by karthrine on 2022/1/12.
//

#import "JYCallStackSymbol.h"
#import <mach/mach.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/dyld.h>
#include <mach-o/nlist.h>





@implementation JYCallStackSymbol

// header头
typedef struct {
    const struct mach_header *header;
    const char *name;
    uintptr_t slide;
} JYMachHeader;


typedef struct {
    JYMachHeader *array;
    uint32_t allocLength;
} JYMachHeaderArr;

static JYMachHeaderArr *machHeaderArr = NULL;


void callStackOfSymbol(uintptr_t *backtraceBuffer, int length ,JYCallStackInfo *csInfo){
    
    for (int i = 0; i<length; i++) {
        // 获取当前lr地址 所在的MachO中的Header
        JYMachHeader * machHeader = getLrInMach(backtraceBuffer[i]);
        if (machHeader) {
            //在header中找到这个LR符号
            findSymbolInMach(backtraceBuffer[i],machHeader,csInfo);
        }
    }
}

// 在machO中找到header
JYMachHeader *getLrInMach(uintptr_t lr)
{
    if (!machHeaderArr) {
        // 获取所有的image镜像文件加入到machHeaderArr，machHeaderArrm里面放的都是header
        getMachHeader();
    }
    
    // 开始循环所有的image,确定当前的指令是在哪个image当中
    for (uint32_t i = 0; i < machHeaderArr->allocLength; i++) {
        // 拿到每个image的header
        JYMachHeader *machHeader = &machHeaderArr->array[i];
        
        // 开始查找lr寄存器中的指令是在哪一个image当中
        if (backtraceBufferItemInMach(lr-machHeader->slide, machHeader->header)) {
            // 找到在哪个image当中 然后返回 对应的machHeader
            return machHeader;
        }
    }
    return NULL;
}


 
bool backtraceBufferItemInMach(uintptr_t slideLR, const struct mach_header *header)
{
    // 向下偏移1个mach_header长度也就是 Load Commands的位置
    // cur 也就是  Load Commands的位置
    uintptr_t cur = (uintptr_t)(((struct mach_header_64*)header) + 1);
    
    // 遍历loadCommands，确认lr是否落在当前image的某个segment中.
   
    // 开始循环 ncmds: loadcommands的数量.
    for (uint32_t i = 0; i < header->ncmds; i++) {
       
        // 将Load Commands的起始位置开始赋值给command
        struct load_command *command = (struct load_command *)cur;
       
         // 判断command 类型是否为 LC_SEGMENT_64, 使用结构体segment_command_64
        if (command->cmd == LC_SEGMENT_64) {
            // 将command换成结构体 segment_command_64 的格式
            struct segment_command_64 *segmentCommand = (struct segment_command_64 *)command;
           
            // command的起始位置
            uintptr_t start = segmentCommand->vmaddr;
            
            // command 的 起始位置 + command的大小 得到  开始start 和 结束end 的位置
            uintptr_t end = segmentCommand->vmaddr + segmentCommand->vmsize;
            
            // 然后开始判断我们存在数组中的数据 是否存在于 这个区间 存在则返回
            if (slideLR >= start && slideLR <= end) {
                // 如果LR的地址落在这个模块里,则返回映像索引号
                return true;
            }
        }
        
#warning TODO
        // 如果command 类型为 LC_SEGMENT，则需要使用结构体segment_command
       
        
        // command地址是连续的，移动到下一个command的位置
        cur = cur + command->cmdsize;
    }
    return false;
}

// 获取mach-O的Header
void getMachHeader(void){
    // 开辟空间
    machHeaderArr = (JYMachHeaderArr *)malloc(sizeof(JYMachHeaderArr));
  
    //_dyld_image_count 获取所有的image的数量
    machHeaderArr->allocLength = _dyld_image_count();

    // 获取第一个image的基址
//    intptr_t  base_addr = _dyld_get_image_vmaddr_slide(0);

    
    //image当中的
    machHeaderArr->array = (JYMachHeader *)malloc(sizeof(JYMachHeader) * machHeaderArr->allocLength);
   
    for (uint32_t i = 0; i < machHeaderArr->allocLength; i++) {
        JYMachHeader *machHeader = &machHeaderArr->array[i];
        
        //获取image的头
        machHeader->header = _dyld_get_image_header(i);
        
        
        //获取image的名称
        machHeader->name = _dyld_get_image_name(i);
        
        //获取进程中单个image加载的Slide值
        // Slide 代表默认在内存中加载的基地址
        machHeader->slide = _dyld_get_image_vmaddr_slide(i);
    }
}



/*
 *  sym_vmaddr(符号表虚拟地址) - vmaddr(LINKEDIT虚拟地址) = symoff(符号表文件地址) - fileoff(LINKEDIT文件地址)
 *  sym_vmaddr = vmaddr - fileoff + symoff
 *  因为 符号表内存真实地址 = sym_vmaddr + slide
 *  所以 符号表真实内存地址 = vmaddr - fileoff + symoff + slide
 *  此函数只为计算 vmaddr - fileoff
 */

void findSymbolInMach(uintptr_t lr, JYMachHeader * machHeader, JYCallStackInfo * csInfo){
    
    if (!machHeader) {
        return;
    }
    
    //  用于保存__LINKEDIT段的结构体 __LINKEDIT段包含动态链接器使用的原始数据，如符号、字符串和重定位表项。
    struct segment_command_64 * seg_linkedit = NULL;
    
    // 用于保存LC_SYMTAB Command的信息 里面有符号表的信息
    struct symtab_command * symtable_command = NULL;
    
    // machO的header
    const struct mach_header * header = machHeader->header;
    
    // 向下偏移1个mach_header长度也就是 Load Commands的位置
    // cur 也就是  Load Commands的位置
    uintptr_t cur = (uintptr_t)(((struct mach_header_64*)header) + 1);
    
    // 遍历Load Commands,找到 LC_SYMTAB 段
    for (uint32_t i = 0; i<header->ncmds; i++) {
        
        // 将Load Commands的起始位置开始赋值给command
        struct load_command * command = (struct load_command*)cur;
      
        if (command->cmd == LC_SEGMENT_64) {
            struct segment_command_64 * segmentCommand = (struct segment_command_64 *)command;
        
            // 我们需要找到__LINKEDIT段 也就是 SEG_LINKEDIT
            // __LINKEDIT段包含动态链接器使用的原始数据，如符号、字符串和重定位表项。
            if (strcmp(segmentCommand->segname, SEG_LINKEDIT) == 0) {
                seg_linkedit = segmentCommand;
            }
        
        }else if (command->cmd == LC_SYMTAB){
            /*
             LC_SYMTAB 描述了string表和symbol表在__LINKEDIT中的位置
             而symbol表描述了符号的地址信息，以及符号对应的字符串（函数名）在string表中的位置
             
             uint32_t    symoff;        符号表offset
             uint32_t    nsyms;         符号表项的数目
             uint32_t    stroff;        字符串表便宜
             uint32_t    strsize;       在字符串表中大小(以字节为单位)
            */
            symtable_command = (struct symtab_command*)command;
        }
        
        // command地址是连续的，移动到下一个command的位置
        cur = cur + command->cmdsize;
    }
    
    // 非空判断
    if (!seg_linkedit || !symtable_command) {
        return;
    }
    
    /*
     我们backtraceBuffer当中lr的地址
     seg_linkedit->vmaddr = LINKEDIT虚拟地址
     seg_linkedit->fileoff = LINKEDIT的文件地址
     (uintptr_t)machHeader->slide  = ASLR
     
     
     lr的偏移地址 = lr真实地址 - ASLR
     
     拿到__LINKEDIT的基地址， segment的基地址  + ASLR = segment加载进内存的基地址 这里叫做linkedit_base
     
     在LC_SYMTAB拿到符号表的偏移 sym_command->symoff  +  linkedit_base  =  符号表symbolTable
     
     所以 stringTable = segment真实地址 + symtabCmd->stroff 符号表的偏移地址;
     
     
     然后因为我们的lr真实地址 只是一条指令地址，它应该大于等于这个函数的入口地址，也就是对应符号的值
     我们应该遍历所有符号表条目 找到距离lr最近的那个函数入口地址 才是最准确的
     所有遍历 Symbol Tabel 获取所有的 symbol.n_value 然后与 lr的偏移地址做比较
     得到一个最接近与lr偏移地址的 symbol.n_value
        
     
     funcInfo->symbol 也就等于 stringTable字符串表  + symtab[best].n_un.n_strx(获取符号名在字符表中的偏移地址，best 代表符号表中的栏目第几个)
     
     */
    
    // segment加载进内存的基地址 =  ASLR + LINKEDIT虚拟地址 - LINKEDIT的文件地址
    uintptr_t linkedit_base = (uintptr_t)machHeader->slide + seg_linkedit->vmaddr - seg_linkedit->fileoff;
    
    // 符号表真实地址 = 符号表的虚拟地址  + symoff偏移地址
    struct nlist_64 *symbolTable = (struct nlist_64 *)(linkedit_base + symtable_command->symoff);
    
    // 字符串表对应的位置
    const uintptr_t stringTable = linkedit_base + symtable_command->stroff;
    
    uintptr_t slideLR = lr - machHeader->slide;
     
    uint64_t offset = UINT64_MAX;
    
    int best = -1;
    
    // 遍历所有符号,找到与LR最近的那个. symtable_command->nsyms指示了符号表的条目
    for (uint32_t i = 0; i < symtable_command->nsyms; i++) {
        
        // 找到距离最近的那一个符号    lr偏移地址 -  符号的地址 = 得到两者之间的距离 distance
        uint64_t distance = slideLR - symbolTable[i].n_value;
        if (slideLR >= symbolTable[i].n_value && distance <= offset) {
            offset = distance;
            best = i;
        }
    }
                    
    
    if (best >= 0) {
        JYFuncInfo *funcInfo = &csInfo->stacks[csInfo->length++];
        funcInfo->machOName = machHeader->name;
        funcInfo->address = symbolTable[best].n_value;
        funcInfo->offset = offset;
        
        // 去字符串表中寻找对应的符号名称，记录符号的虚拟地址+aslr
        // symtab[best].n_un.n_strx 获取符号名在字符表中的偏移地址
        // 虚拟地址+aslr 得到符号的地址 然后 拿到地址里面的字符串
        funcInfo->symbol = (char *)(stringTable + symbolTable[best].n_un.n_strx);
        
        // 去掉下划线
        if (*funcInfo->symbol == '_')
        {
          // char里储存的是0～255的数，然后呢，显示出来是字符（按照Ascii表）。
          //  ++ --是对数字来运算的 所以 这里就是去掉下划线而已
            funcInfo->symbol++;
        }
        if (funcInfo->machOName == NULL) {
            funcInfo->machOName = "";
        }
    }
}


@end
