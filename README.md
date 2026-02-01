# l2-rollup-engine

A Layer-2 rollup engine implementing transaction execution, batching, state transitions, and L1 settlement for Ethereum.  
Built for protocol-level learning and experimentation.



## Overview

`l2-rollup-engine` is an educational yet infrastructure-aligned implementation of an Ethereum Layer-2 rollup.  
The project focuses on the **core mechanics of rollups** rather than product features, making it suitable for understanding how modern L2s like Optimism, Arbitrum, and zkRollups work internally.

The engine models the full L2 flow:
- Transaction intake
- Sequencer-driven execution
- State transition generation
- Batch construction
- L1 settlement interfaces



## Architecture (High Level)

Flow for  transaction :

User Tx
  ↓
Sequencer
  ↓
Execution Engine (EVM)
  ↓
State Transition
  ↓
Batch Builder
  ↓
L1 Settlement Contract (mock / interface)
