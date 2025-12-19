# YYModel 现状审阅与迭代路线（中文）

## 审阅结论摘要
- 现有实现以性能优先为主，但在并发安全、循环引用、容器元素转换、NSValue/struct 输出等场景存在明显正确性风险。
- 多处路径可能导致崩溃或错误数据：日期解析器线程不安全、`ModelToJSONObjectRecursive` 无循环检测、`yy_modelIsEqual` 依赖 `hash`。
- 元数据缓存无淘汰机制，长期运行/动态类多的场景会带来不可控的内存占用。
- 需要先修稳定性再做性能优化，最后补齐生态支持与合规要求。

## 代码层问题清单（带定位）
- 线程安全：`YYNSDateFromString` 与 `YYISODateFormatter` 使用共享 `NSDateFormatter`，并发解析存在竞态与崩溃风险（`YYModel/NSObject+YYModel.m:134-280`）。
- 容器元素自动转换缺失：`NSArray/NSSet` 指定 `genericCls` 时仅接受同类型对象或字典，不做基础类型转换（字符串<->数字），易出现数组为空（`YYModel/NSObject+YYModel.m:894-917`）。
- 循环引用/深度递归：`ModelToJSONObjectRecursive` 无循环检测，模型含 `delegate`/互相引用时会死循环或栈溢出（`YYModel/NSObject+YYModel.m:1150-1279`）。
- `yy_modelHash/yy_modelIsEqual` 稳定性：`yy_modelIsEqual` 先比 `hash`，默认 `hash` 可能导致误判；`yy_modelHash` 基于 KVC 读取属性，遇到指针/C 字符串可能触发异常（`YYModel/NSObject+YYModel.m:1732-1762`）。
- `NSValue/struct` 输出缺失：`yy_modelToJSONObject` 未处理 `NSValue`（如 `CGRect/CGSize`），导致字段丢失（`YYModel/NSObject+YYModel.m:1180-1207`）。
- 运行时字符串转换崩溃：`YYClassMethodInfo` 对 `method_copyArgumentType` 返回值直接 `stringWithUTF8String`，编码异常时可能崩溃（`YYModel/YYClassInfo.m:116-145`）。
- 缓存与内存：`YYClassInfo/_YYModelMeta` 使用全局缓存且无淘汰策略，长期运行会持续占用内存（`YYModel/YYClassInfo.m:260+`, `YYModel/NSObject+YYModel.m:620+`）。
- 批量转换峰值：大量对象转换缺少局部 `@autoreleasepool`，易出现内存峰值。

## Issues 摘要（来自 GitHub 开放问题）
- #329 大量数据转换内存泄漏/占用过高：建议在批量解析路径加入 `@autoreleasepool` + 容量预估。
- #325 / #190 数组元素基础类型转换失败：`NSArray<NSNumber *>` 无法从字符串数组自动转换，反向亦然。
- #324 指针类型属性导致 `modelHash` 崩溃：KVC 不兼容指针/C 字符串类型。
- #321 / #303 `ModelToJSONObjectRecursive` 崩溃：高风险路径，需要类型保护与循环检测。
- #292 模型含 `delegate` 导致 `modelToJSON` 死循环：需循环检测或忽略弱引用属性。
- #270 / #269 `NSValue/struct` 无法输出为 JSON：需要明确输出策略（字符串化或结构拆解）。
- #278 `yy_modelIsEqual` 依赖 `hash` 导致误判（已有 PR #279）。
- #187 / #256 `YYClassMethodInfo initWithMethod:` 崩溃（C 字符串转 UTF8 问题）。
- #311 线程安全讨论 + PR #312（线程安全修复建议）。
- #322 `NSDecimalNumber` 精度问题。
- #294 子类不继承父类 `modelCustomPropertyMapper`。
- #328 需要 Apple Privacy Manifest（`PrivacyInfo.xcprivacy`）。

## 现代化架构设计（保持兼容的前提下分层）
1. **YYModelCore（元数据/反射）**
   - 解析属性/类型、缓存、快速 getter/setter 调用。
   - 缓存改为 `NSCache`，提供 `clearCache`/`trimCache` 等显式清理接口。
2. **YYModelTransform（类型转换管线）**
   - 统一处理 `NSString/NSNumber/NSDate/NSURL/NSDecimalNumber/NSValue` 转换。
   - 支持容器元素基础类型自动转换 + 可插拔 `ValueTransformer`。
3. **YYModelJSON（序列化/反序列化）**
   - 增加循环检测与深度限制；输出策略可配置（映射 key 或属性名）。
   - 日期解析使用线程安全实现：`NSISO8601DateFormatter`（iOS 10+）或线程局部 formatter。
4. **YYModelInterop（生态/Swift/SPM）**
   - Swift Package Manager 支持（#331）。
   - Swift 兼容层（泛型容器映射与 `Codable` 并存）。

## 性能与内存优化目标
- **批量解析内存峰值**：数组/字典遍历使用 `@autoreleasepool`；容器使用 `initWithCapacity:` 预估容量。
- **减少对象创建**：减少重复 `isValidJSONObject` 检测；针对热点路径引入快速路径。
- **缓存策略**：`YYClassInfo/_YYModelMeta` 改为可控缓存，支持清理与容量上限。
- **线程安全开销**：引入轻量锁（`os_unfair_lock`/读写锁），降低全局互斥开销。

## 迭代路线（阶段规划）
### 阶段 0：基线与验证（1-2 周）
- 补齐 Benchmark 与回归基准。
- 加入崩溃/异常场景测试：循环引用、指针属性、NSValue、容器类型转换。

### 阶段 1：稳定性与正确性（2-4 周）
- 修复容器元素基础类型转换（#325/#190）。
- 调整 `yy_modelIsEqual`（移除 `hash` 预判，参考 PR #279）。
- `yy_modelHash` 对指针/C 字符串属性做跳过或 try/catch 保护（#324）。
- `ModelToJSONObjectRecursive` 增加循环检测与深度限制（#292/#218）。
- `NSValue/struct` 序列化策略（#269/#270）。
- `YYClassMethodInfo` 字符串转码安全化（#187/#256）。

### 阶段 2：性能与内存（2-4 周）
- 批量解析路径加入 `@autoreleasepool` 与容量预估（#329）。
- 统一线程安全日期解析器（#312）。
- 缓存策略升级为可控缓存（`NSCache` + 手动清理）。

### 阶段 3：生态与合规（2-3 周）
- SPM 支持（#331）。
- Apple Privacy Manifest（#328）。
- 文档完善：类型转换矩阵、映射策略、循环引用说明。

## 落地优先级
1. 先修正会导致崩溃/错误数据的路径（循环/NSValue/容器转换/`yy_modelIsEqual`）。
2. 再优化性能与内存峰值（`@autoreleasepool` + 预分配 + 缓存策略）。
3. 最后完成生态与合规（SPM/Privacy Manifest/文档）。

