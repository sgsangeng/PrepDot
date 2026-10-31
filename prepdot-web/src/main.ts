import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { createWebAdapters } from './adapters/web'
import { createRuntime, setRuntime } from './runtime'
import './styles/tokens.css'
import './styles/base.css'
import './styles/components.css'

setRuntime(createRuntime(createWebAdapters()))
createApp(App).use(createPinia()).mount('#app')
