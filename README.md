# Multi-Agent System for Forest Fire Extinction (BDI-GIS Architecture)

A cognitive **Multi-Agent System (MAS)** based on the **BDI** (*Belief-Desire-Intention*) architecture for coordinating heterogeneous resources in forest fire extinction. Built on **GAMA Platform (GAML)** with real GIS data from the **Sierra de Gredos**, Spain.

The core of the project is the comparison of two organizational paradigms: a **hierarchical centralized model** and a **decentralized cooperative model** (*peer-to-peer*).

<p align="center">
  <img src="assets/simulacion.gif" alt="Multi-Agent System Demo" width="60%" />
</p>

---

## 🤖 Agents

| Agent | Role | Preview |
|-------|------|---------|
| `recon_drone` | Patrols the map, detects fire outbreaks and coordinates alert propagation | <img src="assets/drone.png" width="80"/> |
| `bombero_terrestre` | Ground unit. Navigates via real road network with stress/fatigue dynamics | <img src="assets/bombero_terrestre.png" width="80"/> |
| `bombero_aereo` | Aerial unit. Free movement, higher speed and water capacity | <img src="assets/bombero_aereo.png" width="80"/> |
| `coordinador` | Active only in centralized mode. Dispatches resources and avoids redundancy | <img src="assets/coordinador.png" width="80"/> |
| `logistics_base` | Physical anchor for ground units and recharge point | <img src="assets/base.png" width="80"/> |

---

## 📊 Organizational Models

**Centralized (hierarchical):** All alerts are routed to a coordinator agent at the base, which prioritizes outbreaks and dispatches the optimal resources synchronously.

**Decentralized (P2P):** No central node exists. Agents negotiate autonomously via the **Contract Net Protocol (CNP)**, electing the lowest-cost unit for each outbreak through a bidding process. Belief propagation between drones *(gossip)* ensures orphaned outbreaks are eventually covered even when all units are busy.

---

## 📂 Project Structure

```
code/
├── includes/          # Real GIS data (DEM, roads, hydrology, fuel types)
├── models/            # GAML source code
│   ├── main.gaml
│   ├── environment.gaml
│   ├── agente_operativo.gaml
│   ├── recon_drone.gaml
│   ├── bombero_terrestre.gaml
│   ├── bombero_aereo.gaml
│   ├── coordinador.gaml
│   └── metrics.gaml
└── results/           # CSV experiment logs and functional test records
assets/                # Agent PNG icons
```

---

## 🚀 Installation

### Prerequisites
- [GAMA Platform](https://gama-platform.org/) 1.9.3 or higher
- Git with [Git LFS](https://git-lfs.com/) installed

### Clone

```bash
git clone https://github.com/bherranz/BDA-Multiagent-System-Fire-Simulation.git
cd BDA-Multiagent-System-Fire-Simulation
git lfs pull
```

### Run

1. Import the `code/` folder as an existing project in your GAMA workspace.
2. Open `models/main.gaml`.
3. Select the desired experiment and launch the simulation.
