<script setup lang="ts">
import DeckFormSheet from './DeckFormSheet.vue'
import type { Deck } from '@/core/api/types'

defineProps<{ deck: Deck; decks: Deck[] }>()
const emit = defineEmits<{ saved: [deck: Deck]; close: [] }>()
</script>

<template>
  <DeckFormSheet
    :deck="deck"
    :decks="decks"
    @saved="emit('saved', $event)"
    @close="emit('close')"
  />
</template>
