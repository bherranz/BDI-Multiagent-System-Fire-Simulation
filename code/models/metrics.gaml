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
    action export_functional_log {
        string modelo <- is_centralized_model ? "Centralizado" : "Descentralizado";
        string filename <- "../results/functional/" + id_prueba + ".md";

        string content <- "# " + id_prueba + "\n\n";
        content <- content + "**Resultado:** ✅ PASS  \n";
        content <- content + "**Modelo:** " + modelo + "  \n";
        content <- content + "**Ciclo de extinción:** " + cycle + "\n\n";
        content <- content + "## Mensajes clave\n\n";
        content <- content + "```\n";
        loop msg over: log_buffer {
            content <- content + msg + "\n";
        }
        content <- content + "```\n";

        save content to: filename format: "string" rewrite: true;
        write "Log exportado: " + filename;
    }

    // Control de finalización inteligente
    reflex check_extinction when: every(10 #cycles) and ciclo_extincion = -1 {
        if (cycle > 50 and world.burning_count = 0) {
            ciclo_extincion <- cycle;

            agua_total_terrestre <- sum(bombero_terrestre collect (each.total_agua_gastada));
            agua_total_aerea     <- sum(bombero_aereo     collect (each.total_agua_gastada));
            int   celdas_quemadas <- world.burned_count;
            float pct_quemado     <- (celdas_quemadas / float(length(terrain_cell))) * 100.0;
            string modelo         <- is_centralized_model ? "Centralizado" : "Descentralizado";

            if (tipo_ejecucion = "FUNCIONAL") {
                do log_msg("[Extinción] Ciclo=" + ciclo_extincion
                    + " | Celdas quemadas=" + celdas_quemadas
                    + " (" + round(pct_quemado) + "%)"
                    + " | Agua terrestre=" + int(agua_total_terrestre) + "L"
                    + " | Agua aérea=" + int(agua_total_aerea) + "L");
                do export_functional_log;
                log_buffer <- []; // Limpiar buffer tras exportar
                do pause;
            }

            else if (tipo_ejecucion = "EXPERIMENTAL") {
                string filename <- "../results/registro_experimentos.csv";
                bool is_new_file <- !file_exists(filename);
                if (is_new_file) {
                    string headers <- "ID_Escenario;Ejecucion;Modelo;Ciclo_Extincion;Celdas_Quemadas;Pct_Quemado;Focos_Detectados;Evacuaciones;Agua_Terrestre_L;Agua_Aerea_L" + "\n";
                    save headers to: filename format: "string" rewrite: true;
                }

                string data_row <- escenario_id + ";"
                                 + ejecucion_num + ";"
                                 + modelo + ";"
                                 + ciclo_extincion + ";"
                                 + celdas_quemadas + ";"
                                 + round(pct_quemado) + ";"
                                 + total_focos_detectados + ";"
                                 + total_evacuaciones + ";"
                                 + int(agua_total_terrestre) + ";"
                                 + int(agua_total_aerea) + "\n";
                save data_row to: filename format: "string" rewrite: false;
                write "Fila añadida al log maestro experimental.";
                do pause;
            }
        }
    }
}

// --- EXPERIMENTO CON TELEMETRÍA ---
experiment Fire_Simulation type: gui {
    parameter "ID Prueba / Escenario"         var: id_prueba   category: "Control de Experimento" init: "PF-000";
    parameter "ID Escenario (Experimental)"   var: escenario_id  category: "Control de Experimento" init: "TEST-00";
    parameter "Nº Ejecución"                  var: ejecucion_num category: "Control de Experimento" init: 1;
    parameter "Tipo de Ejecución"             var: tipo_ejecucion category: "Control de Experimento";
    parameter "Modelo Centralizado"           var: is_centralized_model                                    category: "Arquitectura de Agentes";
    parameter "Tamaño Flota Drones"           var: drone_fleet_size          min: 1   max: 20              category: "Arquitectura de Agentes";
    parameter "Tamaño Flota Terrestre"        var: firefighter_fleet_size    min: 0   max: 10              category: "Arquitectura de Agentes";
    parameter "Tamaño Flota Aérea"            var: aerial_firefighter_fleet_size min: 0 max: 5             category: "Arquitectura de Agentes";
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
        monitor "Intensidad viento"    value: wind_intensity;
        monitor "Msgs en buffer"       value: length(log_buffer);

        display "Gredos 3D Map" type: opengl {
            grid terrain_cell elevation: altitude triangulation: true;
            species road;
            species water_point;
            species logistics_base;
            species recon_drone;
            species bombero_terrestre;
            species bombero_aereo;
            species coordinador;
// Para arrancar el punto de ignición de forma manual
//            event #mouse_down action: {
//		        terrain_cell clicked_cell <- terrain_cell(#user_location);
//		        if (clicked_cell != nil and !clicked_cell.is_burning and !clicked_cell.is_burned) {
//		            ask clicked_cell {
//		                is_burning <- true;
//		                color      <- COLOR_BURNING;
//		                burning_count <- burning_count + 1;
//		            }
//		            write "🔥 Fuego iniciado manualmente en " + #user_location;
//		        }
//		    };
        }
    }
}
