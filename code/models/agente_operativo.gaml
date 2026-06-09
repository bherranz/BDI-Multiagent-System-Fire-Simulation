/**
* Name: Agente Operativo (Clase Base)
* Description: Estructura unificada para unidades de extinción (Terrestres y Aéreas).
* Aplica el principio DRY (Don't Repeat Yourself) y unifica la ontología.
*/

model GredosAgenteOperativo

import "parameters.gaml"
import "environment.gaml"
import "coordinador.gaml"

species agente_operativo control: simple_bdi skills: [moving] {
    
    // --- ATRIBUTOS ONTOLÓGICOS COMUNES ---
    float carga_agua;
    string estado_operativo <- "Disponible"; // Disponible | Extinguiendo | Recargando | Retirada | Repostando | En vuelo
    point foco_asignado <- nil;
    float radio_mision   <- 150.0;
	float prioridad_mision <- 4.0;
	list<point> patrol_route <- []; // Registro de focos para retomar tras retirada
	bool repostaje_notificado <- false;

    
    // --- VARIABLES INTERNAS DE CONTROL ---
    int focos_iniciales <- 0;
    float progreso_ultimo_reporte <- -1.0;
    
    // Semáforos para evitar "spam" en las comunicaciones (Protocolos 4, 5 y 8)
    bool refuerzos_pedidos <- false;
    bool retirada_notificada <- false;
    bool emergencia_notificada <- false;
    
    // Mapa local de creencias sobre focos (Protocolo 3 - Modelo Descentralizado P2P)
    map<point, string> creencias_focos_local <- map([]);

    // --- PREDICADOS BDI COMUNES ---
    string DESEO_EXTINGUIR <- "extinguir_foco";
    string DESEO_RECARGAR_AGUA <- "recargar_agua";
    string DESEO_SUPERVIVENCIA <- "autoproteccion";

    // --- FUNCIONES VIRTUALES ---
    // Cada hijo calculará su propia penalización basándose en sus limitaciones físicas
    action calcular_penalizacion_recursos type: float {
	    return 0.0;
	}

    // Cada hijo evalúa sus propios recursos
	action puede_aceptar_mision type: bool {
	    return false; // Base siempre rechaza, los hijos sobreescriben
	}
	
    // --- ACCIONES COMUNES ---
	// Protocolo 2: Acción unificada de aceptación de misión
	action request_mission(point target_location) {
	    bool puede <- false;
	    ask self { puede <- puede_aceptar_mision(); }
	    
	    if (puede) {
	        write "🟢 [Protocolo 2] " + name + ": AGREE — Aceptando misión en " + target_location;
	        foco_asignado <- target_location;
	        geometry initial_zone <- circle(radio_mision) at_location target_location;
	        focos_iniciales <- length((terrain_cell overlapping initial_zone) where (each.is_burning));
	        do add_desire(predicate(DESEO_EXTINGUIR), prioridad_mision);
	        refuerzos_pedidos <- false;
	        retirada_notificada <- false;
	        emergencia_notificada <- false;
	
	        // Registrar foco como asignado en el coordinador si está en rango
	        if (is_centralized_model and !empty(coordinador)) {
	            coordinador coord <- one_of(coordinador);
	            if ((self distance_to coord) <= coord.coverage_range) {
	                ask coord {
	                    list<point> coincidentes <- assigned_fires where (each distance_to target_location < assignment_radius);
	                    if (empty(coincidentes)) {
	                        assigned_fires <- assigned_fires + [target_location];
	                    }
	                }
	            }
	        }
	    } else {
	        write "🔴 [Protocolo 2] " + name + ": REFUSE";
	    }
	}
    
    
	// RNF-04: Comportamiento autónomo cuando el coordinador no cubre al agente
	reflex autonomia_local when: is_centralized_model 
        and estado_operativo = "Disponible" 
        and foco_asignado = nil
        and every(10 #cycles)
        and (empty(coordinador) or (self distance_to one_of(coordinador)) > one_of(coordinador).coverage_range) {
        
        if (!empty(creencias_focos_local)) {
            point foco_cercano <- creencias_focos_local.keys with_min_of (each distance_to self);
            if (creencias_focos_local[foco_cercano] = "activo") {
                write "[RNF-04] " + name + ": Out of coordinator range. Acting autonomously at " + foco_cercano;
                do request_mission(foco_cercano);
            }
        }
    }

    // Protocolo 2 CNP: calcular y devolver coste estimado para una puja
    action calcular_puja(point ubicacion_foco) type: float {
	    if (estado_operativo != "Disponible") { return #max_float; }
	    float coste_distancia <- location distance_to ubicacion_foco;
	    float penalizacion <- 0.0;
	    ask self { penalizacion <- calcular_penalizacion_recursos(); }
	    return coste_distancia + penalizacion;
	}

    // Protocolo 3 P2P: Sincronización de memoria en modo descentralizado
    action recibir_broadcast_estado(point ubicacion, string estado, float progreso) {
        creencias_focos_local[ubicacion] <- estado;
        write "📡 [Protocolo 3 - P2P] " + name + ": Sincroniza foco " + ubicacion + " → " + estado;
    }
    
    action notify_mission_completion {
	    point finished_target <- foco_asignado;
	    
	    // Búsqueda de restos antes de liberarse
	    geometry sweep_zone <- circle(400.0) at_location finished_target;
	    list<terrain_cell> residual_fires <- (terrain_cell overlapping sweep_zone) where (each.is_burning);
	    if (!empty(residual_fires)) {
	        terrain_cell nearest_residual <- residual_fires with_min_of (each distance_to self);
	        write "🔍 " + name + ": Restos detectados. Continuando en " + nearest_residual.location;
	        foco_asignado <- nearest_residual.location;
	        geometry new_zone <- circle(radio_mision) at_location foco_asignado;
	        focos_iniciales <- length((terrain_cell overlapping new_zone) where (each.is_burning));
	        return; // No liberar, continuar con el deseo activo
	    }
	
	    // Protocolo 9: notificar finalización
	    write "✅ [Protocolo 9] " + name + ": Inform(misionCompletada(foco=" + finished_target + "))";
	    if (is_centralized_model) {
	        if (!empty(coordinador)) {
	            coordinador coord <- one_of(coordinador);
	            if ((self distance_to coord) <= coord.coverage_range) {
	                ask coord { do receive_mission_completion(myself, finished_target); }
	            }
	        }
	    } else {
	        list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < 1500.0);
	        ask nearby_drones { do receive_mission_completion(finished_target); }
	    }
	
	    // Resetear estado completo
	    foco_asignado          <- nil;
	    estado_operativo       <- "Disponible";
	    refuerzos_pedidos      <- false;
	    retirada_notificada    <- false;
	    emergencia_notificada  <- false;
	    repostaje_notificado   <- false;
	    progreso_ultimo_reporte <- -1.0;
	    do remove_desire(predicate(DESEO_EXTINGUIR));
	}
}
