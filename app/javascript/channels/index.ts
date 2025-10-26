// Unified ActionCable consumer for both custom channels and Turbo Streams
import consumer from './consumer'
import { connectStreamSource } from '@hotwired/turbo'

// Configure Turbo Streams to use the same consumer (shared WebSocket connection)
connectStreamSource(consumer)

export default consumer
