const reveals = document.querySelectorAll('.reveal');
const observer = new IntersectionObserver(entries => {
  entries.forEach(entry => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  });
}, { threshold: .12 });
reveals.forEach(item => {
  const rect = item.getBoundingClientRect();
  if (rect.top < window.innerHeight && rect.bottom > 0) {
    item.classList.add('visible');
  } else {
    observer.observe(item);
  }
});

const card = document.querySelector('#tilt-card');
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
if (card && !reduceMotion && window.matchMedia('(pointer: fine)').matches) {
  card.addEventListener('pointermove', event => {
    const rect = card.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width - .5;
    const y = (event.clientY - rect.top) / rect.height - .5;
    card.style.transform = `perspective(900px) rotateY(${x * 8}deg) rotateX(${-y * 8}deg)`;
  });
  card.addEventListener('pointerleave', () => { card.style.transform = ''; });
}
