# JYThreadMonitor
记录线程监控数量、开启等监控


```C++
 [JYThreadMonitor startMonitor];
```


主要实现原理是通过

```
  // 添加🪝钩子函数
  original_pthread_introspection_hook_t = pthread_introspection_hook_install(jy_pthread_introspection_hook_t);
```


实现原理介绍可以看这篇文章
https://juejin.cn/post/7047414349870628871

其中记录堆栈的详细说明可以看这两篇文章
[iOS如何记录堆栈信息？(一)](https://juejin.cn/post/7049267131036205086)
[iOS如何记录堆栈信息？(二)](https://juejin.cn/post/7052712362180083749)
