package com.prepdot.algorithm;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class FsrsSchedulerTest {

    private final FsrsScheduler scheduler = new FsrsScheduler();

    @Test
    void retrievability_atElapsedZero_isOne() {
        assertEquals(1.0, scheduler.retrievability(10.0, 0), 0.0001);
    }

    @Test
    void retrievability_whenElapsedEqualsStability_isAlways0point9() {
        // 稳定性的定义就是"降到 90% 需要的天数"，这条对任意 S 都成立
        assertEquals(0.9, scheduler.retrievability(3.7145, 3.7145), 0.0001);
        assertEquals(0.9, scheduler.retrievability(15.0, 15.0), 0.0001);
    }

    @Test
    void initialState_rating3Good_matchesHandCalculation() {
        FsrsState state = scheduler.initialState(3);
        assertEquals(3.7145, state.stability(), 0.0001);
        assertEquals(5.1618, state.difficulty(), 0.0001);
    }

    @Test
    void initialState_rating1Again_hasLowestStability() {
        FsrsState state = scheduler.initialState(1);
        assertEquals(0.4872, state.stability(), 0.0001);
    }

    @Test
    void initialState_rating4Easy_hasHighestStabilityAndLowestDifficulty() {
        FsrsState easy = scheduler.initialState(4);
        FsrsState again = scheduler.initialState(1);
        assertTrue(easy.stability() > again.stability());
        assertTrue(easy.difficulty() < again.difficulty());
    }

    @Test
    void reviewExisting_successfulRating_neverDecreasesStability() {
        FsrsState before = new FsrsState(5.0, 3.7145);
        for (int rating : new int[]{2, 3, 4}) { // hard, good, easy 都算"成功召回"
            FsrsState after = scheduler.reviewExisting(before, rating, 4.0);
            assertTrue(after.stability() >= before.stability(),
                    "rating=" + rating + " 后稳定性不应该比复习前更低");
        }
    }

    @Test
    void reviewExisting_forgetRating_producesPositiveStability() {
        FsrsState before = new FsrsState(5.1618, 3.7145);
        FsrsState after = scheduler.reviewExisting(before, 1, 4.0);
        assertTrue(after.stability() > 0, "忘记之后稳定性应该重置为一个正数，而不是 0 或负数");
        assertTrue(after.stability() < before.stability() * 3,
                "忘记之后不应该反而比复习前的稳定性大很多倍");
    }

    @Test
    void reviewExisting_difficultyAlwaysStaysInBounds() {
        FsrsState extreme = new FsrsState(1.0, 1.0);
        for (int rating = 1; rating <= 4; rating++) {
            FsrsState after = scheduler.reviewExisting(extreme, rating, 10.0);
            assertTrue(after.difficulty() >= 1.0 && after.difficulty() <= 10.0,
                    "难度必须裁剪在 [1,10]，实际是 " + after.difficulty());
        }
    }

    @Test
    void reviewExisting_goodRatingAfterFourDays_regressionSnapshot() {
        // golden master：这个值是跑代码得到的真实输出，锁住是为了防止以后改代码时无意破坏行为
        FsrsState state = new FsrsState(5.1618, 3.7145);
        FsrsState after = scheduler.reviewExisting(state, 3, 4.0);
        assertEquals(5.1618, after.difficulty(), 0.001);
        assertEquals(14.8081, after.stability(), 0.001);
    }

    @Test
    void nextIntervalDays_atTargetRetention0point9_equalsStabilityRounded() {
        assertEquals(4, scheduler.nextIntervalDays(3.7145)); // round(3.7145) = 4
        assertEquals(15, scheduler.nextIntervalDays(15.0));
    }

    @Test
    void nextIntervalDays_neverReturnsLessThanOne() {
        assertTrue(scheduler.nextIntervalDays(0.01) >= 1);
    }
}
