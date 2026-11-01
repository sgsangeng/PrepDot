<script setup lang="ts">
import DeckFormSheet from './DeckFormSheet.vue'
import type { Deck } from '@/core/api/types'

defineProps<{ decks: Deck[] }>()
const emit = defineEmits<{ saved: [deck: Deck]; close: [] }>()
</script>

<template>
  <DeckFormSheet
    :decks="decks"
    @saved="emit('saved', $event)"
    @close="emit('close')"
  />
</template>
