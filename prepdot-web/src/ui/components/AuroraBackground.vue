<template>
  <div
    class="aurora"
    aria-hidden="true"
  >
    <span class="blob blob-indigo" />
    <span class="blob blob-purple" />
    <span class="blob blob-teal" />
  </div>
</template>

<style scoped>
.aurora {
  position: fixed;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  pointer-events: none;
  background: var(--bg);
}

.blob {
  position: absolute;
  width: 60vmax;
  height: 60vmax;
  border-radius: 50%;
  filter: blur(90px);
  opacity: 0.55;
  will-change: transform;
}

.blob-indigo {
  top: -22vmax;
  left: -18vmax;
  background: radial-gradient(
    circle at center,
    color-mix(in srgb, var(--color-indigo) 55%, transparent),
    transparent 68%
  );
  animation: drift-a 18s ease-in-out infinite alternate;
}

.blob-purple {
  top: 8vmax;
  right: -24vmax;
  background: radial-gradient(
    circle at center,
    color-mix(in srgb, var(--color-purple) 48%, transparent),
    transparent 68%
  );
  animation: drift-b 22s ease-in-out infinite alternate;
}

.blob-teal {
  bottom: -30vmax;
  left: 12vmax;
  background: radial-gradient(
    circle at center,
    color-mix(in srgb, var(--color-teal) 34%, transparent),
    transparent 70%
  );
  animation: drift-c 26s ease-in-out infinite alternate;
}

@keyframes drift-a {
  from { transform: translate3d(0, 0, 0) scale(1); }
  to { transform: translate3d(8vmax, 6vmax, 0) scale(1.08); }
}

@keyframes drift-b {
  from { transform: translate3d(0, 0, 0) scale(1.05); }
  to { transform: translate3d(-10vmax, 8vmax, 0) scale(1); }
}

@keyframes drift-c {
  from { transform: translate3d(0, 0, 0) scale(1); }
  to { transform: translate3d(6vmax, -6vmax, 0) scale(1.1); }
}
</style>
