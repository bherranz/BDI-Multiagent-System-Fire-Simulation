/**
* Name: Métricas y control de la simulación
* Description: Telemetría en tiempo real, detección de extinción,
* exportación de logs y parada automática de la simulación.
*/

model GredosMetrics

import "parameters.gaml"
import "environment.gaml"
import "bombero_terrestre.gaml"
import "bombero_aereo.gaml"
import "recon_drone.gaml"
import "coordinador.gaml"

global {
    // --- MÉTRICAS ---
    int total_focos_detectados <- 0;
    int total_evacuaciones     <- 0;
    float agua_total_terrestre <- 0.0;
    float agua_total_aerea     <- 0.0;
    int ciclo_extincion        <- -1;

    // Llamado por los agentes para registrar evacuaciones (P8)
    action registrar_evacuacion {
        total_evacuaciones <- total_evacuaciones + 1;
    }

    // RF-07: Detectar extinción total, exportar log y pausar
    reflex check_extinction when: every(10 #cycles) and ciclo_extincion = -1 {
        if (cycle > 100 and world.burning_count = 0) {
            ciclo_extincion <- cycle;

            agua_total_terrestre <- sum(bombero_terrestre collect (firefighter_max_water      - each.carga_agua));
            agua_total_aerea     <- sum(bombero_aereo     collect (aerial_firefighter_max_water - each.carga_agua));

            int   celdas_quemadas <- world.burned_count;
            float pct_quemado     <- (celdas_quemadas / float(length(terrain_cell))) * 100.0;
            string modelo         <- is_centralized_model ? "Centralizado" : "Descentralizado";

            write "==================================================";
            write "SIMULACIÓN FINALIZADA — Modelo: " + modelo;
            write "Ciclo de extinción total:  " + ciclo_extincion;
            write "Celdas quemadas:           " + celdas_quemadas + " (" + round(pct_quemado) + "% del mapa)";
            write "Focos detectados:          " + total_focos_detectados;
            write "Evacuaciones de emergencia:" + total_evacuaciones;
            write "Agua — Terrestres: " + int(agua_total_terrestre) + "L | Aéreos: " + int(agua_total_aerea) + "L";
            write "==================================================";

            string filename <- "resultados_" + modelo + "_ciclo" + ciclo_extincion + ".csv";
            save ["modelo", "ciclo_extincion", "celdas_quemadas", "pct_quemado",
                  "focos_detectados", "evacuaciones", "agua_terrestre_L", "agua_aerea_L"]
                 to: filename format: "csv" rewrite: true;
            save [modelo, ciclo_extincion, celdas_quemadas, round(pct_quemado),
                  total_focos_detectados, total_evacuaciones,
                  int(agua_total_terrestre), int(agua_total_aerea)]
                 to: filename format: "csv" rewrite: false;

            write "Log exportado: " + filename;
            do pause;
        }
    }
}

// --- EXPERIMENTO CON TELEMETRÍA ---
experiment Fire_Simulation type: gui {
    parameter "Modelo Centralizado"           var: is_centralized_model                                    category: "Arquitectura de Agentes";
    parameter "Tamaño Flota Drones"           var: drone_fleet_size          min: 5   max: 20              category: "Arquitectura de Agentes";
    parameter "Tamaño Flota Terrestre"        var: firefighter_fleet_size    min: 2   max: 10              category: "Arquitectura de Agentes";
    parameter "Tamaño Flota Aérea"            var: aerial_firefighter_fleet_size min: 1 max: 5             category: "Arquitectura de Agentes";
    parameter "Capacidad de Base (slots)"     var: base_capacity             min: 1   max: 5               category: "Arquitectura de Agentes";
    parameter "Epsilon (incertidumbre)"       var: epsilon_base              min: 0.0 max: 0.1             category: "Modelo de Fuego";
    parameter "Duración Quemado (Ciclos)"     var: cell_burn_duration        min: 5   max: 100             category: "Modelo de Fuego";
    parameter "Dirección Viento (Grados)"     var: wind_direction            min: 0.0 max: 360.0           category: "Modelo de Viento";
    parameter "Intensidad Viento"             var: wind_intensity            min: 0.5 max: 5.0             category: "Modelo de Viento";
    parameter "Factor de Pendiente"           var: slope_influence_factor    min: 0.001 max: 0.02          category: "Modelo de Terreno";

    output {
        monitor "Ciclo actual"         value: cycle;
        monitor "Celdas ardiendo"      value: world.burning_count;
        monitor "Celdas quemadas"      value: world.burned_count;
        monitor "Focos detectados"     value: total_focos_detectados;
        monitor "Evacuaciones"         value: total_evacuaciones;
        monitor "Bomberos disponibles" value: length(bombero_terrestre where (each.estado_operativo = "Disponible"));
        monitor "Helicópteros disp."   value: length(bombero_aereo     where (each.estado_operativo = "Disponible"));
        monitor "Drones en patrulla"   value: length(recon_drone       where (each.has_desire(predicate("patrol_area"))));

        display "Gredos 3D Map" type: opengl {
            grid terrain_cell elevation: altitude triangulation: true;
            species road;
            species water_point;
            species logistics_base;
            species recon_drone;
            species bombero_terrestre;
            species bombero_aereo;
            species coordinador;
        }
    }
}