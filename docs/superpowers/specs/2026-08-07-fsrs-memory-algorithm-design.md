# PrepDot 记忆算法升级：FSRS-4.5 落地设计

- 日期：2026-08-07
- 背景：[技术方案.md](../../../技术方案.md) 6.2 节已记录当前算法是"简化版间隔重复规则（非完整 SM-2）"，并将"升级为真正的 SM-2"列为待办。本设计替换该待办，直接落地 FSRS-4.5，而非 SM-2。
- 目标：作为简历/面试可深挖的技术点，用一个真实、可验证、公开发表的算法替换现在的固定 delta 规则；范围严格限定在核心算法落地，不做个性化参数优化、不做知识图谱增强（见"范围外"一节）。

## 1. 现状

`PlanServiceImpl.submitReview()`（[PlanServiceImpl.java:88-95](../../../prepdot-backend/src/main/java/com/prepdot/service/impl/PlanServiceImpl.java#L88)）用固定的分数增减 + 固定天数表：

```
again: -18 分，0 天后重新出现
hard : +3  分，1 天后
good : +12 分，2-4 天后（复习次数 <2 时 2 天，否则 4 天）
easy : +20 分，5-10 天后（复习次数 <2 时 5 天，否则 10 天）
```

`Flashcard` 表用一个整数 `memoryScore`（0-100）表示"记忆度"，`reviewCount` 记录复习次数，没有对每张卡片的记忆规律做个体化建模。

## 2. 目标算法：FSRS-4.5

FSRS（Free Spaced Repetition Scheduler）是 Anki 自 2023.10 起的默认调度算法，核心是 **DSR 模型**：Difficulty（难度，1-10）、Stability（稳定性，天数）、Retrievability（可提取性，0-1 概率，是稳定性和经过天数的函数，不持久存储）。

以下公式取自 open-spaced-repetition 项目的官方 wiki（[来源](https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm)），**实现前请对照该仓库当前版本源码再核对一遍权重数值**——这类开源项目会随新版本调整默认权重，写代码前拿最新值可以避免"文档过时"的偏差。

### 2.1 默认权重（17 个，w0-w16）

```
[0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
 1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755]
```

### 2.2 可提取性（遗忘曲线）

```
R(t, S) = (1 + FACTOR · t/S) ^ DECAY
DECAY = -0.5，FACTOR = 19/81
```
其中 `t` = 距上次复习经过的天数，`S` = 当前稳定性。约束：`R(S, S) = 0.9`（稳定性的定义就是"降到 90% 保留率所需天数"）。

### 2.3 下次间隔

```
I(r, S) = (S / FACTOR) · (r^(1/DECAY) - 1)
```
`r` = 目标保留率，本设计固定为 **0.9**（不做成可配置项，见问题澄清阶段的决定）。结果四舍五入取整数天，`again` 走现有系统的"0 天后立即重新出现"分支（复用现有逻辑，不属于 FSRS 公式本身）。

### 2.4 初始状态（首次评分，G ∈ {1=again, 2=hard, 3=good, 4=easy}）

```
S0(G) = w[G-1]          // 即 w0/w1/w2/w3 分别对应四档评分
D0(G) = w4 - (G-3)·w5   // D0(3) = w4，是"good"评分下的基准难度
```

### 2.5 后续复习的难度更新

```
D'(D, G) = w7·D0(3) + (1-w7)·(D - w6·(G-3))
```
即先按评分调整，再向基准难度 `D0(3)` 做均值回归，最终裁剪到 `[1, 10]`。

### 2.6 后续复习的稳定性更新

评分为 hard/good/easy（记住了）：
```
S'success = S · ( e^w8 · (11-D) · S^-w9 · (e^(w10·(1-R)) - 1) · [w15 if G=hard] · [w16 if G=easy] + 1 )
```

评分为 again（忘记了）：
```
S'forget = w11 · D^-w12 · ((S+1)^w13 - 1) · e^(w14·(1-R))
```

`R` 取的是**这次复习发生前**、按 2.2 公式算出的可提取性。

## 3. 数据模型变更

`flashcard` 表新增两个字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `difficulty` | DOUBLE | 1-10，FSRS 的 D |
| `stability` | DOUBLE | 天数，FSRS 的 S |

`memoryScore` 字段**保留但改变语义**：不再是"复习时写死的静态值"，而是查询卡组/计划接口时，服务层用 `retrievability(difficulty, stability, elapsedDays) × 100` 实时算出，塞进返回的 VO。理由：R 本质是时间的函数，卡片放着不复习时它应该持续下降，写死的静态值会立刻过期；改成"按需计算"不需要定时任务或触发器，查询时算一次即可，YAGNI。

`review_record.memoryScoreBefore/After` 同理：`Before` = 复习前那一刻按公式算出的 R×100；`After` 固定取接近 100 的值（FSRS 语义里刚完成一次复习即视为满可提取性）。

## 4. Java 实现结构

新增 `com.prepdot.algorithm.FsrsScheduler`：纯函数类，不依赖 Spring/MyBatis，方便脱离数据库单测。

```java
public record FsrsState(double difficulty, double stability) {}
public record FsrsReviewResult(FsrsState newState, int nextIntervalDays) {}

public class FsrsScheduler {
    public FsrsReviewResult review(FsrsState state, String rating, double elapsedDays, boolean isFirstReview);
    public double retrievability(FsrsState state, double elapsedDays);
}
```

`PlanServiceImpl.submitReview()` 改造范围：只替换第 88-97 行那段 `switch` 计分逻辑，改为读取 `card.difficulty/stability` → 调用 `FsrsScheduler.review()` → 用返回值写回 `difficulty/stability/nextReviewAt/reviewCount`。校验越权、写复习记录、更新当日计划项等其余逻辑不动。

## 5. 已有卡片的迁移策略

**全部重置，当作新卡片处理**：迁移脚本把所有现有卡片的 `difficulty`/`stability` 置空（或不设初始值），下次复习时按 2.4 节"首次评分"分支重新初始化，不去凑一个 `memoryScore → D/S` 的反推公式。原因：反推公式没有理论依据，纯粹凑数字，面试时立不住；重置的代价只是老卡片短期内的间隔预测不够准，但不影响真实数据质量，而且 `review_record` 里的历史记录完整保留，不会丢数据。

## 6. 测试策略

- `FsrsScheduler` 纯函数单测，覆盖：首次评分四档、连续 `again` 不会导致稳定性坍缩为负数、难度裁剪在 `[1,10]`、连续 `easy` 的间隔增长趋势合理
- 有条件的话，从 open-spaced-repetition 官方测试集里挑几组已知输入/输出作为回归测试用例
- `PlanServiceImpl.submitReview()` 集成测试沿用现有测试方式，验证接线正确（读对字段、写对字段），不重复测算法本身

## 7. 范围外（本次不做，但设计上不堵路）

- **个性化参数优化**：用 `review_record` 历史数据为每个用户拟合专属权重。FSRS 官方设计本身包含这部分，本次不做，但 `FsrsScheduler` 把权重数组作为参数传入（而非硬编码全局单例），为以后按用户传不同权重留了口子。
- **知识图谱增强**（关联卡片间的记忆传播）：官方 FSRS 不具备的能力，是 PrepDot 相对于"抄一遍开源库"的真正差异化方向，但复杂度高，本次不做。
- **AI 辅助初始难度先验**：不做。

## 8. 风险与待核实项

- 2.1-2.6 节公式和权重值是通过 WebFetch 从 open-spaced-repetition 官方 wiki 转录的，**动手写代码前建议再核对一次官方仓库当前版本**，避免权重值随算法迭代（FSRS-5/6）有变化导致文档和实现不一致。
- `memoryScore` 语义变更（存储值→实时计算值）如果有其他地方（如 `UserStatsVO` 统计接口）直接读这个字段做聚合，需要确认改造范围是否需要覆盖到这些统计接口——本设计未展开排查，留给实现计划阶段做代码扫描确认。
