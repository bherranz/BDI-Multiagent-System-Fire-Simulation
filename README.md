# Multi-Agent System for Forest Fire Extinction (BDI-GIS Architecture)

Este repositorio contiene el código fuente y los entornos de simulación de un **Sistema Multiagente (SMA) cognitivo-deliberativa** basado en la arquitectura **BDI** (*Belief-Desire-Intention*) para la optimización y coordinación de recursos heterogéneos en la extinción de incendios forestales. 

El simulador está desarrollado sobre **GAMA Platform (GAML)** e integra de forma nativa datos espaciales y topográficos de Sistemas de Información Geográfica (GIS) reales correspondientes a la **Sierra de Gredos**, España. El objetivo principal del proyecto es evaluar y comparar el rendimiento de dos paradigmas organizacionales: un modelo jerárquico centralizado y un modelo descentralizado cooperativo (*peer-to-peer*).

---

## 📹 Simulación

A continuación se muestra una grabación de la simulación en ejecución dentro de GAMA Platform, donde se puede observar el comportamiento autónomo de las unidades en un renderizado 3D sobre el relieve real de la Sierra de Gredos, la propagación dinámica del fuego mediante un autómata celular adaptado a la pendiente y el viento, y el flujo de los protocolos de coordinación:


![Demostración del Sistema Multiagente](code/includes/simulacion.gif)
---

## 🤖 Representación de Agentes en la Simulación

Cada unidad operativa del servicio de emergencias está modelada bajo la arquitectura cognitiva BDI y cuenta con una representación visual y espacial específica dentro de la interfaz gráfica del simulador:

* **🛸 Dron de Reconocimiento (`recon_drone`):** Representado como un **icono aéreo estilizado en color cian/azul claro**. Su misión principal es patrullar el mapa de forma estocástica o planificada para detectar nuevos focos de ignición y actualizar las *creencias* globales o compartidas del sistema.
* **🚒 Bombero Terrestre / Autobomba (`bombero_terrestre`):** Representado en el entorno como un **camión/vehículo de emergencias rojo**. Su movilidad está restringida de forma híbrida por la red vial real (OpenStreetMap). Cuenta con un componente psicofísico donde factores dinámicos como el **estrés** y el **cansancio** modifican su eficacia operativa y disparan protocolos de autoprotección y retirada táctica.
* **🚁 Helicóptero de Extinción (`bombero_aereo`):** Representado como un **icono de aeronave en color amarillo o naranja**. Posee movilidad libre (vectorial bidimensional) sobrevolando el relieve, mayor velocidad de desplazamiento y una capacidad de carga hídrica superior para ataques directos sobre los focos.
* **📡 Nodo Coordinador (`coordinador`):** Ubicado espacialmente en la **Base de Operaciones (icono de base/casa)**. Solo está activo en la arquitectura centralizada, donde centraliza la telemetría, mantiene un registro persistente de tareas pendientes y despacha proactivamente recursos para evitar redundancias.
* **💧 Puntos de Recarga (`water_points`):** Representados como **esferas/iconos azules** en el mapa, extraídos de la hidrografía GIS real, donde los bomberos y helicópteros deben acudir a reabastecer sus tanques de agua cuando agotan su autonomía.

### 📂 Estructura del Proyecto

El código fuente y los entornos lógicos del simulador están organizados en los siguientes bloques principales dentro del entorno GAMA:

* **`code/includes/` (Cartografía y Datos GIS Reales):** Contiene todos los ficheros espaciales extraídos de fuentes oficiales que dan forma al entorno de la Sierra de Gredos. Incluye el Modelo Digital de Elevaciones (MDE) para el relieve en 3D, y las capas vectoriales para la red de carreteras de OpenStreetMap, la hidrografía y la tipología de combustibles forestales.
* **`code/models/` (Lógicas de Simulación en GAML):** Es el núcleo de programación del sistema multiagente. Aquí se encuentran el archivo principal de entrada (`main.gaml`), la definición del entorno dinámico y el autómata celular del fuego (`environment.gaml`), las reglas cognitivas de la arquitectura base (`agente_operativo.gaml`) y los comportamientos específicos de cada rol (drones de patrulla, helicópteros, coordinadores y bomberos terrestres).
* **`code/results/` (Métricas y Almacenamiento de Datos):** Carpeta destinada a guardar los datos brutos generados por el sistema. Alberga las memorias lógicas de las pruebas funcionales de aceptación y, de forma centralizada, el archivo maestro CSV (`registro_experimentos.csv`) con las métricas de las 36 simulaciones masivas.
* **`code/script.py` (Script de Analítica Estadística):** Módulo externo desarrollado en Python que procesa automáticamente el archivo de resultados CSV para generar las gráficas de rendimiento, las medias y las desviaciones típicas necesarias para el análisis cuantitativo.

---

### 📊 Modelos Organizativos

El núcleo de la investigación consiste en analizar cómo interactúa la flota ante dos configuraciones organizativas radicalmente opuestas:

1.  **Modelo Centralizado Jerárquico:** Todas las alertas e incidencias detectadas por las unidades de reconocimiento son enviadas en tiempo real a una Base Central. Un agente coordinador global procesa las solicitudes, prioriza los focos más críticos y despacha de forma síncrona los recursos óptimos para evitar la duplicidad de esfuerzos.
2.  **Modelo Descentralizado Cooperativo (P2P):** No existe ninguna base ni nodo central que distribuya las tareas. Los propios agentes interactúan y toman decisiones locales de forma autónoma utilizando protocolos de subasta basados en el **Contract Net Protocol (CNP)**, demostrando una alta tolerancia a fallos en entornos de comunicaciones complicados.

---

### 🚀 Requisitos e Instalación

#### 1. Clonación del Repositorio (Git LFS)

Debido al peso de las capas cartográficas reales de la Sierra de Gredos, el repositorio está configurado con **Git Large File Storage (LFS)**. Para clonar el proyecto de forma correcta asegurando que se descarguen todos los binarios, ejecuta en tu terminal:

```bash
git clone [https://github.com/bherranz/BDA-Multiagent-System-Fire-Simulation.git](https://github.com/bherranz/BDA-Multiagent-System-Fire-Simulation.git)
cd BDA-Multiagent-System-Fire-Simulation
git lfs pull
```

#### 2. Ejecución del Simulador

* Descarga e instala **GAMA Platform** (versión 1.9.3 o superior).
* Importa la carpeta `code/` como un proyecto existente en tu espacio de trabajo (*Workspace*).
* Abre el fichero `models/main.gaml` y selecciona el experimento deseado
