# YYModel 现状审阅与迭代路线（中文）

> **审阅日期**：2025-12-19  
> **基于版本**：当前 main 分支最新代码

## 审阅结论摘要

- 现有实现以性能优先为主，核心功能已较为完善，线程安全、缓存策略、循环检测等关键问题已得到改进。
- **已修复的问题**：日期解析器线程安全（使用线程局部存储）、缓存策略（已改用 `NSCache` + 容量限制）、循环检测（已实现但默认关闭）、`NSValue/struct` 输出（已支持常见结构体）。
- **仍需改进的问题**：容器元素基础类型转换仍有局限、循环检测默认关闭需显式启用、Privacy Manifest 和 SPM 完善。
- 建议：先补齐容器转换和循环检测的默认行为，再优化性能，最后完成生态与合规要求。

---

## 代码层问题清单（带定位）

### ✅ 已修复的问题

| 问题 | 原始描述 | 当前状态 | 代码位置 |
|------|----------|----------|----------|
| 线程安全：日期解析器 | 共享 `NSDateFormatter` 存在竞态 | ✅ 已使用线程局部存储 `[[NSThread currentThread] threadDictionary]` | `NSObject+YYModel.m:137-149` |
| 缓存无淘汰策略 | 全局缓存无容量限制 | ✅ 已改用 `NSCache` + `countLimit` + 内存警告清理 | `NSObject+YYModel.m:757-771`, `YYClassInfo.m:343-361` |
| 循环引用检测 | `ModelToJSONObjectRecursive` 无循环检测 | ✅ 已实现循环检测和深度限制（需通过 `modelToJSONObjectUsesCycleDetection` 启用） | `NSObject+YYModel.m:1340-1346, 1375-1414, 1604-1614` |
| `yy_modelIsEqual` hash 预判 | 先比 `hash` 导致误判 | ✅ 已移除 hash 预判，直接比较属性值 | `NSObject+YYModel.m:2087-2108` |
| `yy_modelHash` 异常保护 | 遇到指针/C 字符串可能触发异常 | ✅ 已有 try-catch 保护，并跳过非 KVC 兼容属性 | `NSObject+YYModel.m:2067-2085` |
| `NSValue/struct` 输出 | `yy_modelToJSONObject` 未处理 `NSValue` | ✅ 已支持 CGRect/CGPoint/CGSize 等常见结构体的字符串输出 | `NSObject+YYModel.m:1319-1337, 1367-1371` |
| 字符串转码崩溃 | `method_copyArgumentType` 直接 UTF8 转换 | ✅ 已使用安全的 `YYStringFromUTF8` 函数处理编码异常 | `YYClassInfo.m:18-23, 149-151` |
| 批量转换内存峰值 | 大量对象转换无 `@autoreleasepool` | ✅ 已在容器遍历和批量方法中添加 `@autoreleasepool` | `NSObject+YYModel.m:1044, 1094, 2142` |

### ⚠️ 仍需改进的问题

| 问题 | 描述 | 风险等级 | 代码位置 |
|------|------|----------|----------|
| 容器元素类型转换 | `NSArray/NSSet` 指定 `genericCls` 时，基础类型间的转换（如字符串↔数字）仍有局限，可能导致元素丢失 | 中 | `NSObject+YYModel.m:1043-1060` |
| 循环检测默认关闭 | 循环检测功能已实现，但**默认关闭**，对于有 delegate/互相引用的模型需显式启用 | 中 | `NSObject+YYModel.m:1606-1609` |
| `NSDecimalNumber` 精度 | 从字符串解析 `NSDecimalNumber` 时部分边界情况可能丢失精度 | 低 | `NSObject+YYModel.m:973-986` |
| 子类继承 `modelCustomPropertyMapper` | 已通过 `YYModelMergedDictionaryFromClass` 合并父类配置，但需验证复杂继承场景 | 低 | `NSObject+YYModel.m:310-333, 644` |

---

## Issues 摘要（来自 GitHub 开放问题）

### 已解决或已有方案的 Issues

| Issue | 描述 | 状态 |
|-------|------|------|
| #329 | 大量数据转换内存泄漏/占用过高 | ✅ 已添加 `@autoreleasepool` + 容量预估 |
| #311 / #312 | 线程安全问题 | ✅ 已使用线程局部存储 |
| #292 / #218 | `modelToJSON` 循环引用死循环 | ✅ 已实现循环检测（需启用） |
| #269 / #270 | `NSValue/struct` 无法输出为 JSON | ✅ 已支持常见结构体 |
| #278 / #279 | `yy_modelIsEqual` 依赖 `hash` 导致误判 | ✅ 已移除 hash 预判 |
| #187 / #256 | `YYClassMethodInfo` 字符串转换崩溃 | ✅ 已使用安全转换函数 |
| #294 | 子类不继承父类 `modelCustomPropertyMapper` | ✅ 已通过合并字典解决 |

### 待完善的 Issues

| Issue | 描述 | 优先级 |
|-------|------|--------|
| #325 / #190 | 数组元素基础类型转换失败 | 高 |
| #321 / #303 | `ModelToJSONObjectRecursive` 边界类型保护 | 中 |
| #324 | 指针类型属性导致异常（已有保护，可进一步优化） | 低 |
| #322 | `NSDecimalNumber` 精度问题 | 低 |
| #328 | Apple Privacy Manifest（`PrivacyInfo.xcprivacy`） | 中 |
| #331 | Swift Package Manager 支持 | 中 |

---

## 现代化架构设计（保持兼容的前提下分层）

### 1. YYModelCore（元数据/反射）
- 解析属性/类型、缓存、快速 getter/setter 调用
- ✅ 已完成：`NSCache` 缓存 + 容量限制 + 内存警告响应
- 待优化：提供显式 `clearCache`/`trimCache` 公开接口

### 2. YYModelTransform（类型转换管线）
- 统一处理 `NSString/NSNumber/NSDate/NSURL/NSDecimalNumber/NSValue` 转换
- ✅ 已完成：基础类型转换、`NSValue` struct 支持
- 待优化：容器元素基础类型自动转换 + 可插拔 `ValueTransformer`

### 3. YYModelJSON（序列化/反序列化）
- ✅ 已完成：循环检测（深度限制 32）+ `visited` 集合
- ✅ 已完成：日期解析使用线程安全实现（线程局部 formatter）
- 待优化：循环检测默认开启或提供全局配置

### 4. YYModelInterop（生态/Swift/SPM）
- ✅ 已有：`Package.swift` 基础支持
- 待完善：Swift 兼容层（泛型容器映射与 `Codable` 并存）

---

## 性能与内存优化目标

| 目标 | 当前状态 | 待优化 |
|------|----------|--------|
| 批量解析内存峰值 | ✅ 已添加 `@autoreleasepool`；容器使用 `initWithCapacity:` | - |
| 减少对象创建 | 部分实现 | 针对热点路径引入快速路径 |
| 缓存策略 | ✅ `NSCache` + 容量上限 + 内存警告清理 | 暴露公开清理接口 |
| 线程安全开销 | 使用 `dispatch_semaphore` | 考虑 `os_unfair_lock` 降低开销 |

---

## 迭代路线（阶段规划）

### 阶段 0：基线与验证（1-2 周）
- [x] 补齐 Benchmark 与回归基准
- [ ] 加入崩溃/异常场景测试：循环引用、指针属性、NSValue、容器类型转换
- [ ] 验证当前代码的测试覆盖率

### 阶段 1：稳定性与正确性（2-3 周）
- [ ] **修复容器元素基础类型转换**（#325/#190）
  - 在 `ModelSetValueForProperty` 容器处理中增强 `YYModelCreateValueForClass` 调用逻辑
- [ ] **循环检测默认行为**
  - 考虑默认开启或提供全局配置 `[YYModel setDefaultCycleDetectionEnabled:]`
- [ ] 完善 `NSDecimalNumber` 边界处理（#322）

### 阶段 2：性能与内存（1-2 周）
- [ ] 提供公开的缓存清理接口 `+[YYModel clearModelCache]`
- [ ] 评估 `os_unfair_lock` 替代 `dispatch_semaphore` 的可行性
- [ ] 减少重复 `isValidJSONObject` 检测

### 阶段 3：生态与合规（2-3 周）
- [ ] 完善 SPM 支持（#331）
- [x] Apple Privacy Manifest（#328）- 已添加 `PrivacyInfo.xcprivacy`
- [ ] 文档完善：类型转换矩阵、映射策略、循环引用说明
- [ ] Swift 兼容层文档

---

## 落地优先级

1. **高优先级**：容器元素类型转换、循环检测默认行为
2. **中优先级**：公开缓存清理接口、SPM 完善、文档更新
3. **低优先级**：锁优化、Swift 兼容层

---

## 附录：代码关键位置索引

| 功能模块 | 文件 | 行号范围 |
|----------|------|----------|
| 日期解析（线程安全） | `NSObject+YYModel.m` | 137-224 |
| 类型转换核心 | `NSObject+YYModel.m` | 336-407 |
| 属性元数据 | `NSObject+YYModel.m` | 413-545 |
| 模型元数据 | `NSObject+YYModel.m` | 549-785 |
| JSON → Model 转换 | `NSObject+YYModel.m` | 920-1262 |
| Model → JSON 转换 | `NSObject+YYModel.m` | 1342-1615 |
| `yy_modelHash` / `yy_modelIsEqual` | `NSObject+YYModel.m` | 2067-2108 |
| 类信息缓存 | `YYClassInfo.m` | 341-379 |
| 安全字符串转换 | `YYClassInfo.m` | 18-23 |
