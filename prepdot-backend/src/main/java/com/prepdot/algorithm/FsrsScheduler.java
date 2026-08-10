package com.prepdot.algorithm;

import org.springframework.stereotype.Component;

@Component
public class FsrsScheduler {

    private static final double[] DEFAULT_WEIGHTS = {
            0.4872, 1.4003, 3.7145, 13.8206, 5.1618, 1.2298, 0.8975, 0.031,
            1.6474, 0.1367, 1.0461, 2.1072, 0.0793, 0.3246, 1.587, 0.2272, 2.8755
    };
    private static final double DECAY = -0.5;
    private static final double FACTOR = 19.0 / 81.0;
    private static final double TARGET_RETENTION = 0.9;

    private final double[] w;

    public FsrsScheduler() {
        this(DEFAULT_WEIGHTS);
    }

    public FsrsScheduler(double[] weights) {
        if (weights.length != 17) {
            throw new IllegalArgumentException("FSRS-4.5 需要 17 个权重参数，实际收到 " + weights.length + " 个");
        }
        this.w = weights;
    }

    public double retrievability(double stability, double elapsedDays) {
        if (elapsedDays <= 0) {
            return 1.0;
        }
        return Math.pow(1 + FACTOR * elapsedDays / stability, DECAY);
    }

    /** 首次评分（第一次复习这张卡片），rating: 1=again 2=hard 3=good 4=easy */
    public FsrsState initialState(int rating) {
        double stability = w[rating - 1];
        double difficulty = clipDifficulty(w[4] - (rating - 3) * w[5]);
        return new FsrsState(difficulty, stability);
    }

    private double clipDifficulty(double difficulty) {
        return Math.max(1.0, Math.min(10.0, difficulty));
    }

    /** 后续复习（不是第一次评分这张卡片） */
    public FsrsState reviewExisting(FsrsState state, int rating, double elapsedDays) {
        double r = retrievability(state.stability(), elapsedDays);
        double newDifficulty = clipDifficulty(
                w[7] * w[4] + (1 - w[7]) * (state.difficulty() - w[6] * (rating - 3))
        );
        double newStability = (rating == 1)
                ? forgetStability(state.difficulty(), state.stability(), r)
                : successStability(state.difficulty(), state.stability(), r, rating);
        return new FsrsState(newDifficulty, newStability);
    }

    private double successStability(double difficulty, double stability, double r, int rating) {
        double hardPenalty = (rating == 2) ? w[15] : 1.0;
        double easyBonus = (rating == 4) ? w[16] : 1.0;
        double increase = Math.exp(w[8])
                * (11 - difficulty)
                * Math.pow(stability, -w[9])
                * (Math.exp(w[10] * (1 - r)) - 1)
                * hardPenalty
                * easyBonus
                + 1;
        return stability * increase;
    }

    private double forgetStability(double difficulty, double stability, double r) {
        return w[11]
                * Math.pow(difficulty, -w[12])
                * (Math.pow(stability + 1, w[13]) - 1)
                * Math.exp(w[14] * (1 - r));
    }

    /** 目标保留率固定 90%，反推下次复习该等多少天 */
    public int nextIntervalDays(double stability) {
        double days = (stability / FACTOR) * (Math.pow(TARGET_RETENTION, 1.0 / DECAY) - 1);
        return Math.max(1, (int) Math.round(days));
    }
}
