export interface ApiRequest {
  method: 'GET' | 'POST' | 'PUT' | 'DELETE'
  path: string
  body?: unknown
  headers?: Record<string, string>
  signal?: AbortSignal
}

export interface RawResponse<T> {
  status: number
  body: { code: number; message: string; data: T | null }
}

export interface MultipartField {
  name: string
  value: string
}

export interface MultipartFile {
  field: string
  name: string
  mime: string
  bytes: ArrayBuffer
}

export interface MultipartRequest {
  path: string
  fields: MultipartField[]
  file: MultipartFile
  headers?: Record<string, string>
  signal?: AbortSignal
}

export interface HttpTransport {
  json<T>(req: ApiRequest): Promise<RawResponse<T>>
  multipart<T>(req: MultipartRequest): Promise<RawResponse<T>>
  streamText(req: ApiRequest): AsyncIterable<string>
}

export interface StoragePort {
  get(key: string): Promise<string | null>
  set(key: string, value: string): Promise<void>
  remove(key: string): Promise<void>
}

export interface PickedFile {
  name: string
  mime: string
  size: number
  bytes(): Promise<ArrayBuffer>
}

export interface FilePort {
  pick(options: { multiple: boolean; accept: string[] }): Promise<PickedFile[]>
}

export interface NotificationPort {
  permission(): Promise<'granted' | 'denied' | 'default'>
  requestPermission(): Promise<'granted' | 'denied' | 'default'>
  scheduleDaily(time: string, target: number): Promise<void>
  cancelDaily(): Promise<void>
}

export interface ClipboardPort {
  readText(): Promise<string>
}

export interface Clock {
  now(): number
}

export interface AppAdapters {
  storage: StoragePort
  http: HttpTransport
  file: FilePort
  notification: NotificationPort
  clipboard: ClipboardPort
  clock: Clock
}
