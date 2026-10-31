import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from '@/ui/stores/auth'
import { resolveRedirect } from './guard'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', name: 'login', component: () => import('@/ui/pages/LoginPage.vue') },
    { path: '/', redirect: { name: 'review' } },
    { path: '/review', name: 'review', component: () => import('@/ui/pages/ReviewPage.vue') },
    { path: '/decks/:id?', name: 'decks', component: () => import('@/ui/pages/DecksPage.vue') },
    { path: '/decks/:id/quiz', name: 'quiz', component: () => import('@/ui/pages/QuizPage.vue') },
    { path: '/coach', name: 'coach', component: () => import('@/ui/pages/CoachPage.vue') },
    { path: '/profile', name: 'profile', component: () => import('@/ui/pages/ProfilePage.vue') },
    { path: '/profile/reminder', name: 'reminder', component: () => import('@/ui/pages/ReminderPage.vue') },
    { path: '/profile/delete', name: 'delete-account', component: () => import('@/ui/pages/DeleteAccountPage.vue') },
    { path: '/graph', name: 'graph', component: () => import('@/ui/pages/MasteryMapPage.vue') },
    { path: '/generate', name: 'generate', component: () => import('@/ui/pages/AiGeneratePage.vue') },
    { path: '/community', name: 'community', component: () => import('@/ui/pages/CommunityPage.vue') },
    { path: '/:pathMatch(.*)*', redirect: { name: 'review' } }
  ]
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  await auth.restore()
  const redirect = resolveRedirect(auth.isAuthenticated, String(to.name))
  return redirect ? { name: redirect } : true
})

export default router
