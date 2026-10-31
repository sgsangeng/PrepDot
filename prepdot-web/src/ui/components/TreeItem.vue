<script setup lang="ts">
import { computed } from 'vue'
import {
  ChevronDown,
  ChevronRight,
  Layers,
  Network,
  Pencil,
  Trash2
} from 'lucide-vue-next'
import DeckRow from './DeckRow.vue'
import type { DeckNode } from '@/core/decks/tree'
import type { Deck } from '@/core/api/types'

const props = withDefaults(
  defineProps<{
    node: DeckNode
    expandedIds: ReadonlySet<number>
    selectedId?: number | null
    expandAll?: boolean
  }>(),
  { selectedId: null, expandAll: false }
)

const emit = defineEmits<{
  toggle: [id: number]
  edit: [deck: Deck]
  delete: [deck: Deck]
}>()

const hasChildren = computed(() => props.node.children.length > 0)
const isExpanded = computed(() => props.expandAll || props.expandedIds.has(props.node.deck.id))
const isSelected = computed(() => props.selectedId === props.node.deck.id)

const nodeIcon = computed(() => (hasChildren.value ? Network : Layers))

const statusClass = computed(() => {
  const deck = props.node.deck
  if (deck.cardCount === 0) return 'status-muted'
  if (deck.dueCount > 0 || deck.avgMemoryScore < 40) return 'status-red'
  if (deck.avgMemoryScore < 70) return 'status-orange'
  return 'status-green'
})
</script>

<template>
  <li class="tree-node">
    <div
      class="row"
      :class="{ selected: isSelected }"
    >
      <button
        v-if="hasChildren"
        class="toggle"
        type="button"
        :aria-label="isExpanded ? `收起 ${node.deck.title}` : `展开 ${node.deck.title}`"
        :aria-expanded="isExpanded"
        :disabled="expandAll"
        :title="expandAll ? '搜索时自动展开匹配结果' : undefined"
        @click="emit('toggle', node.deck.id)"
      >
        <ChevronDown
          v-if="isExpanded"
          :size="18"
          aria-hidden="true"
        />
        <ChevronRight
          v-else
          :size="18"
          aria-hidden="true"
        />
      </button>
      <span
        v-else
        class="toggle-spacer"
        aria-hidden="true"
      />

      <component
        :is="nodeIcon"
        class="lead-icon"
        :class="statusClass"
        :size="20"
        aria-hidden="true"
      />

      <RouterLink
        class="row-link"
        :to="{ name: 'decks', params: { id: node.deck.id } }"
        :aria-current="isSelected ? 'page' : undefined"
      >
        <DeckRow :deck="node.deck" />
      </RouterLink>

      <div class="actions">
        <button
          class="action"
          type="button"
          :aria-label="`编辑 ${node.deck.title}`"
          title="编辑"
          @click.stop="emit('edit', node.deck)"
        >
          <Pencil
            :size="17"
            aria-hidden="true"
          />
        </button>
        <button
          class="action action-delete"
          type="button"
          :aria-label="`删除 ${node.deck.title}`"
          title="删除"
          @click.stop="emit('delete', node.deck)"
        >
          <Trash2
            :size="17"
            aria-hidden="true"
          />
        </button>
      </div>
    </div>

    <ul
      v-if="hasChildren && isExpanded"
      class="children"
    >
      <TreeItem
        v-for="child in node.children"
        :key="child.deck.id"
        :node="child"
        :expanded-ids="expandedIds"
        :selected-id="selectedId"
        :expand-all="expandAll"
        @toggle="emit('toggle', $event)"
        @edit="emit('edit', $event)"
        @delete="emit('delete', $event)"
      />
    </ul>
  </li>
</template>

<style scoped>
.tree-node {
  min-width: 0;
}

.row {
  display: flex;
  align-items: center;
  gap: 2px;
  min-width: 0;
  min-height: 56px;
  padding: 6px 6px 6px 2px;
  border-radius: var(--radius-sm);
  transition: background 0.15s ease;
}

.row:hover {
  background: var(--surface-muted);
}

.row.selected {
  background: color-mix(in srgb, var(--color-indigo) 9%, transparent);
}

.toggle,
.action {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: 44px;
  padding: 0;
  border: 0;
  border-radius: var(--radius-sm);
  background: transparent;
  color: var(--text-secondary);
}

.toggle:hover,
.action:hover {
  background: var(--surface-muted);
}

.toggle:disabled {
  cursor: default;
  opacity: 0.45;
}

.toggle-spacer {
  flex: none;
  width: 44px;
}

.lead-icon {
  flex: none;
}

.status-muted {
  color: var(--text-tertiary);
}

.status-red {
  color: var(--color-red);
}

.status-orange {
  color: var(--color-orange);
}

.status-green {
  color: var(--color-green);
}

.row-link {
  flex: 1;
  min-width: 0;
  padding: 2px 0;
  border-radius: var(--radius-sm);
  color: inherit;
  text-decoration: none;
}

.actions {
  display: flex;
  flex: none;
  align-items: center;
  gap: 0;
}

.action {
  color: var(--text-tertiary);
}

.action-delete:hover {
  color: var(--color-red);
}

.children {
  margin: 0 0 0 21px;
  padding: 0 0 0 10px;
  border-left: 1px dashed var(--border-strong);
  list-style: none;
}

.toggle:focus-visible,
.action:focus-visible,
.row-link:focus-visible {
  outline: 2px solid var(--color-indigo);
  outline-offset: 2px;
}
</style>
