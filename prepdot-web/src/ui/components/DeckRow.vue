<script setup lang="ts">
import { computed } from 'vue'
import { Clock3, Layers } from 'lucide-vue-next'
import ProgressBar from './ProgressBar.vue'
import type { Deck } from '@/core/api/types'

const props = defineProps<{ deck: Deck }>()

const hasCards = computed(() => props.deck.cardCount > 0)

const tone = computed<'indigo' | 'green' | 'orange' | 'red'>(() => {
  if (!hasCards.value) return 'indigo'
  if (props.deck.avgMemoryScore < 40) return 'red'
  if (props.deck.avgMemoryScore < 70) return 'orange'
  return 'green'
})

const scoreText = computed(() => (hasCards.value ? `${props.deck.avgMemoryScore}%` : '暂无卡片'))
const scoreToneClass = computed(() => (hasCards.value ? `score-${tone.value}` : 'score-muted'))
</script>

<template>
  <div class="deck-row">
    <div class="title-line">
      <span class="deck-title">{{ deck.title }}</span>
      <span class="category-pill">{{ deck.category }}</span>
    </div>

    <p
      v-if="deck.description && deck.description.trim()"
      class="description"
    >
      {{ deck.description }}
    </p>

    <div class="stats">
      <span class="stat">
        <Layers
          :size="13"
          aria-hidden="true"
        />
        <span class="num">{{ deck.cardCount }}</span> 张
      </span>
      <span
        v-if="deck.dueCount > 0"
        class="stat stat-due"
      >
        <Clock3
          :size="13"
          aria-hidden="true"
        />
        <span class="num">{{ deck.dueCount }}</span> 到期
      </span>
      <span
        class="stat score"
        :class="scoreToneClass"
      >
        记忆度 <span class="num">{{ scoreText }}</span>
      </span>
      <ProgressBar
        class="score-bar"
        :value="deck.avgMemoryScore"
        :max="100"
        :tone="tone"
        :aria-label="`${deck.title} 记忆度 ${scoreText}`"
      />
    </div>
  </div>
</template>

<style scoped>
.deck-row {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.title-line {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.deck-title {
  overflow: hidden;
  font-size: 15px;
  font-weight: 700;
  color: var(--text);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.category-pill {
  flex: none;
  padding: 2px 8px;
  border-radius: 999px;
  background: color-mix(in srgb, var(--color-indigo) 12%, transparent);
  color: var(--color-indigo-text);
  font-size: 11px;
  font-weight: 600;
}

.description {
  display: -webkit-box;
  overflow: hidden;
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.5;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  line-clamp: 2;
}

.stats {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 12px;
  font-size: 12px;
  color: var(--text-secondary);
}

.stat {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  white-space: nowrap;
}

.stat-due {
  color: var(--color-orange-text);
}

.score {
  font-weight: 600;
}

.score-bar {
  flex: 1;
  min-width: 56px;
  max-width: 96px;
}

.score-muted {
  color: var(--text-tertiary);
}

.score-red {
  color: var(--color-red-text);
}

.score-orange {
  color: var(--color-orange-text);
}

.score-green {
  color: var(--color-green-text);
}
</style>
