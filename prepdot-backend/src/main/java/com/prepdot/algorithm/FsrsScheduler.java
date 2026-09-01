package com.prepdot.algorithm;

import org.springframework.stereotype.Component;

/**
 * FSRS-4.5 间隔重复调度器。
 *
 * 一张卡片由两个核心状态描述：
 * - difficulty：难度，范围为 1～10，越大越难。
 * - stability：稳定性，表示记忆衰减速度；越大代表忘得越慢。
 *
 * 每次复习流程：
 * 1. 根据距上次复习的时间，计算当前可回忆率 R。
 * 2. 根据本次评分更新难度 D。
 * 3. 根据“忘记/记住”更新稳定性 S。
 * 4. 根据目标保留率，计算下次复习间隔。
 */
@Component
public class FsrsScheduler {

    /**
     * FSRS-4.5 的默认 17 个参数。
     *
     * w[0]～w[3]：首次评分 Again / Hard / Good / Easy 对应的初始稳定性。
     * w[4]～w[7]：难度初始化与难度更新参数。
     * w[8]～w[10]：成功复习后稳定性增长参数。
     * w[11]～w[14]：遗忘后稳定性重建参数。
     * w[15]：Hard 的稳定性增长惩罚。
     * w[16]：Easy 的稳定性增长奖励。
     */
    private static final double[] DEFAULT_WEIGHTS = {

            0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,

            1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755

    };

    /**
     * 遗忘曲线衰减指数。
     * 负数表示：经过的时间越长，可回忆率越低。
     */
    private static final double DECAY = -0.5;

    /**
     * FSRS 遗忘曲线中的比例常数。
     * 与 DECAY 配合，使 stability 的含义与“约 90% 保留率时的间隔”对应。
     */
    private static final double FACTOR = 19.0 / 81.0;

    /**
     * 期望在下次复习时仍能记住的概率：90%。
     */
    private static final double TARGET_RETENTION = 0.9;

    /**
     * 当前调度器使用的 17 个模型参数。
     */
    private final double[] w;

    /**
     * 使用内置默认权重创建调度器。
     */
    public FsrsScheduler() {

        this(DEFAULT_WEIGHTS);

    }

    /**
     * 使用自定义 FSRS 权重创建调度器。
     *
     * @param weights FSRS-4.5 的 17 个权重参数
     */
    public FsrsScheduler(double[] weights) {

        // FSRS-4.5 的这组公式严格依赖 17 个参数。
        if (weights.length != 17) {

            throw new IllegalArgumentException("FSRS-4.5 需要 17 个权重参数，实际收到 " + weights.length + " 个");

        }

        this.w = weights;

    }

    /**
     * 根据稳定性和已经过去的天数，计算当前可回忆率 R。
     *
     * R 的范围通常是 (0, 1]：
     * - elapsedDays = 0 时，认为刚复习过，R = 1。
     * - stability 越大，R 下降越慢。
     * - elapsedDays 越大，R 越低。
     *
     * @param stability 当前稳定性 S
     * @param elapsedDays 距离上次复习经过的天数
     * @return 当前预测可回忆率 R
     */
    public double retrievability(double stability, double elapsedDays) {

        // 尚未经过时间，不发生遗忘。
        if (elapsedDays <= 0) {

            return 1.0;

        }

        // FSRS 遗忘曲线：
        // R = (1 + FACTOR * t / S) ^ DECAY
        return Math.pow(1 + FACTOR * elapsedDays / stability, DECAY);

    }

    /**
     * 首次评分：第一次复习这张卡片。
     *
     * rating:
     * 1 = Again：完全没记住
     * 2 = Hard：记得困难
     * 3 = Good：正常记住
     * 4 = Easy：轻松记住
     *
     * 首次评分没有历史状态，因此直接从权重中取初始稳定性和初始难度。
     */
    public FsrsState initialState(int rating) {

        // w[0]～w[3] 分别对应 Again、Hard、Good、Easy 的初始稳定性。
        // 评分越高，通常初始稳定性越大。
        double stability = w[rating - 1];

        // 初始难度：
        // rating 越低，difficulty 越大；rating 越高，difficulty 越小。
        double difficulty = clipDifficulty(w[4] - (rating - 3) * w[5]);

        return new FsrsState(difficulty, stability);

    }

    /**
     * 把难度限制在 FSRS 规定的有效范围 [1, 10] 内。
     */
    private double clipDifficulty(double difficulty) {

        return Math.max(1.0, Math.min(10.0, difficulty));

    }

    /**
     * 后续复习：已经有历史状态的卡片再次被评分。
     *
     * @param state 当前卡片状态，含上次复习后的 difficulty 与 stability
     * @param rating 本次评分，1=again、2=hard、3=good、4=easy
     * @param elapsedDays 自上次复习以来经过的天数
     * @return 本次评分后的新状态
     */
    public FsrsState reviewExisting(FsrsState state, int rating, double elapsedDays) {

        // 先预测用户在本次复习前本应有多大概率记住。
        double r = retrievability(state.stability(), elapsedDays);

        // 更新难度：
        // - rating < 3：难度上升。
        // - rating > 3：难度下降。
        // - w[7] 使难度向初始难度基准 w[4] 回归，避免长期无限升高或降低。
        double newDifficulty = clipDifficulty(

                w[7] * w[4] + (1 - w[7]) * (state.difficulty() - w[6] * (rating - 3))

        );

        // Again 表示遗忘，使用遗忘公式重新计算稳定性；
        // Hard / Good / Easy 表示成功回忆，使用成功复习公式增加稳定性。
        double newStability = (rating == 1)

                ? forgetStability(state.difficulty(), state.stability(), r)

                : successStability(state.difficulty(), state.stability(), r, rating);

        return new FsrsState(newDifficulty, newStability);

    }

    /**
     * 成功回忆后的稳定性更新。
     *
     * 一般规律：
     * - 卡片越简单，稳定性提升越多。
     * - 旧稳定性较低时，提升空间通常更大。
     * - 本应快忘却时仍答对（R 较低），提升更多。
     * - Hard 会削弱提升。
     * - Easy 会增强提升。
     */
    private double successStability(double difficulty, double stability, double r, int rating) {

        // Hard 时乘以小于 1 的系数，降低稳定性增长幅度。
        double hardPenalty = (rating == 2) ? w[15] : 1.0;

        // Easy 时乘以大于 1 的系数，提高稳定性增长幅度。
        double easyBonus = (rating == 4) ? w[16] : 1.0;

        // increase 是“新的稳定性相对旧稳定性增长多少倍”。
        //
        // (11 - difficulty)：越简单，数值越大，增长越明显。
        // stability ^ (-w[9])：旧稳定性较低的卡片一般有更大的增长空间。
        // exp(w[10] * (1 - r)) - 1：
        //   r 越低，说明越接近遗忘边缘仍成功回忆，增长奖励越大。
        double increase = Math.exp(w[8])

                * (11 - difficulty)

                * Math.pow(stability, -w[9])

                * (Math.exp(w[10] * (1 - r)) - 1)

                * hardPenalty

                * easyBonus

                // +1 保证成功回忆后至少不会让稳定性下降。
                + 1;

        return stability * increase;

    }

    /**
     * 遗忘后的稳定性更新。
     *
     * Again 不代表稳定性一定归零，而是根据：
     * - 卡片难度
     * - 过去已有的稳定性
     * - 本次遗忘前的预测可回忆率
     *
     * 重新估算该卡片的稳定性。
     */
    private double forgetStability(double difficulty, double stability, double r) {

        return w[11]

                // 难度越高，遗忘后的稳定性通常越低。
                * Math.pow(difficulty, -w[12])

                // 旧稳定性仍会影响遗忘后的新稳定性。
                * (Math.pow(stability + 1, w[13]) - 1)

                // 当模型预测本就很难记住时（r 低），遗忘的负面影响相对较小。
                * Math.exp(w[14] * (1 - r));

    }

    /**
     * 按目标保留率反推下次复习间隔。
     *
     * 由遗忘公式：
     * R = (1 + FACTOR * days / stability) ^ DECAY
     *
     * 令 R = TARGET_RETENTION（这里固定为 0.9），解出 days。
     *
     * @param stability 本次复习后得到的新稳定性
     * @return 建议的下次复习间隔，最少 1 天
     */
    public int nextIntervalDays(double stability) {

        double days = (stability / FACTOR) * (Math.pow(TARGET_RETENTION, 1.0 / DECAY) - 1);

        // 四舍五入到整数天，并确保不会出现 0 天或负数间隔。
        return Math.max(1, (int) Math.round(days));

    }
}