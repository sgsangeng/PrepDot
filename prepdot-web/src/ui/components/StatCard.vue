<script setup lang="ts">
/**
 * 个人中心的四格统计小卡片：图标 + 数值 + 标签。
 * 图标通过默认插槽传入（lucide 组件），颜色由 `tone` 控制。
 */
type StatTone = 'indigo' | 'purple' | 'blue' | 'pink'

withDefaults(defineProps<{
  value: string | number
  label: string
  tone?: StatTone
}>(), {
  tone: 'indigo'
})
</script>

<template>
  <div
    class="stat-card"
    :class="`tone-${tone}`"
  >
    <span
      class="stat-icon"
      aria-hidden="true"
    ><slot /></span>
    <span class="stat-value num">{{ value }}</span>
    <span class="stat-label">{{ label }}</span>
  </div>
</template>

<style scoped>
.stat-card {
  --stat-color: var(--color-indigo);

  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  min-width: 0;
  padding: 14px 4px;
  border-radius: 14px;
  background: color-mix(in srgb, var(--stat-color) 8%, transparent);
  text-align: center;
}

.tone-purple { --stat-color: var(--color-purple); }
.tone-blue { --stat-color: var(--color-blue); }
.tone-pink { --stat-color: var(--color-pink); }

.stat-icon {
  display: grid;
  place-items: center;
  color: var(--stat-color);
}

.stat-value {
  overflow-wrap: anywhere;
  font-family: var(--font-rounded);
  font-size: 17px;
  font-weight: 700;
  line-height: 1.2;
}

.stat-label {
  color: var(--text-secondary);
  font-size: 11px;
  line-height: 1.3;
}
</style>
