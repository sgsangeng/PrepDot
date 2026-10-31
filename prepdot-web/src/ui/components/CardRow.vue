<script setup lang="ts">
import { computed } from 'vue'
import { Brain } from 'lucide-vue-next'
import SelectCircle from './SelectCircle.vue'
import TypeBadge from './TypeBadge.vue'
import type { Flashcard } from '@/core/api/types'
import { cardDisplayText, normalizeCardType, typeLabel } from '@/core/format/text'
import { parseCardOptions } from '@/core/review/session'

const props = withDefaults(
  defineProps<{ card: Flashcard; managing?: boolean; selected?: boolean }>(),
  { managing: false, selected: false }
)

defineEmits<{ activate: [] }>()

const cardType = computed(() => normalizeCardType(props.card.cardType))
const badgeTone = computed<'orange' | 'teal'>(() => (cardType.value === 'choice' ? 'orange' : 'teal'))
const options = computed(() =>
  cardType.value === 'choice' ? parseCardOptions(props.card.options) : []
)
const answerText = computed(() => cardDisplayText(props.card.answer))

function optionPrefix(index: number): string {
  return ['A', 'B', 'C', 'D'][index] ?? String(index + 1)
}
</script>

<template>
  <button
    class="card-row"
    :class="{ selected: managing && selected }"
    type="button"
    :aria-pressed="managing ? selected : undefined"
    @click="$emit('activate')"
  >
    <SelectCircle
      v-if="managing"
      :selected="selected"
    />

    <span class="body">
      <span class="question-line">
        <TypeBadge
          v-if="cardType !== 'qa'"
          :label="typeLabel(card.cardType)"
          :tone="badgeTone"
        />
        <span class="question">{{ card.question }}</span>
      </span>

      <template v-if="options.length">
        <span
          v-for="(option, index) in options"
          :key="index"
          class="option"
          :class="{ correct: option === card.answer }"
        >
          <span class="option-prefix">{{ optionPrefix(index) }}</span>
          <span class="option-text">{{ option }}</span>
        </span>
      </template>
      <span
        v-else
        class="answer"
      >{{ answerText }}</span>

      <span class="meta">
        <span class="memory">
          <Brain
            :size="13"
            aria-hidden="true"
          />
          {{ card.memoryScore }}
        </span>
        <span class="review-count">复习 {{ card.reviewCount }} 次</span>
      </span>
    </span>
  </button>
</template>

<style scoped>
.card-row {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  width: 100%;
  min-height: 44px;
  padding: 12px 14px;
  border: 0;
  border-bottom: 1px solid var(--border);
  background: transparent;
  color: var(--text);
  text-align: left;
  transition: background 0.15s ease;
}

.card-row:hover {
  background: var(--surface-muted);
}

.card-row.selected {
  background: color-mix(in srgb, var(--color-indigo) 8%, transparent);
}

.card-row:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: -2px;
}

.body {
  display: flex;
  flex: 1;
  flex-direction: column;
  gap: 5px;
  min-width: 0;
}

.question-line {
  display: flex;
  align-items: flex-start;
  gap: 6px;
  min-width: 0;
}

.question {
  display: -webkit-box;
  overflow: hidden;
  font-size: 15px;
  font-weight: 600;
  line-height: 1.45;
  overflow-wrap: anywhere;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  line-clamp: 2;
}

.answer {
  display: -webkit-box;
  overflow: hidden;
  color: var(--text-secondary);
  font-size: 13px;
  line-height: 1.5;
  white-space: pre-line;
  overflow-wrap: anywhere;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 2;
  line-clamp: 2;
}

.option {
  display: flex;
  align-items: flex-start;
  gap: 7px;
  color: var(--text-secondary);
  font-size: 12px;
  line-height: 1.45;
}

.option.correct {
  color: var(--color-green-text);
  font-weight: 600;
}

.option-prefix {
  flex: none;
  font-weight: 700;
}

.option-text {
  overflow-wrap: anywhere;
}

.meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 4px 12px;
  color: var(--text-secondary);
  font-size: 12px;
}

.memory {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: var(--color-indigo-text);
  font-weight: 600;
}
</style>
