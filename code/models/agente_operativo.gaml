/**
* Name: Agente Operativo (Clase Base)
* Description: Estructura unificada para unidades de extinción (Terrestres y Aéreas).
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
	point foco_original <- nil;
    float radio_mision   <- 150.0;
	float prioridad_mision <- 4.0;
	list<point> patrol_route <- []; // Registro de focos para retomar tras retirada
	bool repostaje_notificado <- false;
	float total_agua_gastada <- 0.0;

	float max_agua_mision <- firefighter_max_water; // Atributo virtual
    
    // --- VARIABLES INTERNAS DE CONTROL ---
    int focos_iniciales <- 0;
    float progreso_ultimo_reporte <- -1.0;
	point destino_recarga <- nil;
    
    // Semáforos para evitar spam en las comunicaciones
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
	        write "[Protocolo 2] " + name + ": AGREE — Aceptando misión en " + target_location;
	        foco_asignado <- target_location;
	        foco_original <- target_location;
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
	        write "[Protocolo 2] " + name + ": REFUSE";
	    }
	}
    
    
	// RNF-04: Comportamiento autónomo cuando el coordinador no cubre al agente
	reflex autonomia_local when: is_centralized_model
	    and estado_operativo = "Disponible" and foco_asignado = nil and every(10 #cycles)
	    and (empty(coordinador) or (self distance_to one_of(coordinador)) > one_of(coordinador).coverage_range) {
	
	    if (!empty(creencias_focos_local)) {
	        // Usar mapa local si tiene datos
	        point foco_cercano <- creencias_focos_local.keys with_min_of (each distance_to self);
	        if (creencias_focos_local[foco_cercano] = "activo") {
	            write "[RNF-04] " + name + ": Fuera de rango. Actuando con mapa local → " + foco_cercano;
	            do request_mission(foco_cercano);
	        }
	    } else {
	        // Fallback: percepción directa del entorno
	        list<terrain_cell> visible <- terrain_cell where
	            (each.is_burning and each distance_to self < 2000.0);
	        if (!empty(visible)) {
	            point foco_cercano <- (visible with_min_of (each distance_to self)).location;
	            write "[RNF-04] " + name + ": Fuera de rango. Percepción directa → " + foco_cercano;
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
        write "[Protocolo 3 - P2P] " + name + ": Sincroniza foco " + ubicacion + " → " + estado;
    }
    
    action notify_mission_completion {
	    point finished_target <- (foco_original != nil) ? foco_original : foco_asignado;
	    // Búsqueda de restos: solo redirigir si hay fuego activo cercano
	    // y el agente tiene agua suficiente para seguir (>20% del máximo)
	    bool tiene_agua <- carga_agua > (max_agua_mision * 0.2);
	    geometry sweep_zone <- circle(400.0) at_location finished_target;
	    list<terrain_cell> residual_fires <- (terrain_cell overlapping sweep_zone)
	        where (each.is_burning);
	
	    if (!empty(residual_fires) and tiene_agua) {
	        terrain_cell nearest_residual <- residual_fires with_min_of (each distance_to self);
	        write name + ": Restos detectados. Continuando en " + nearest_residual.location;
	        foco_asignado <- nearest_residual.location;
	        geometry new_zone <- circle(radio_mision) at_location foco_asignado;
	        focos_iniciales <- length((terrain_cell overlapping new_zone) where (each.is_burning));
	        return;
	    }
	
	    // Protocolo 9: notificar finalización
	    write "[Protocolo 9] " + name + ": Inform(misionCompletada(foco=" + finished_target + "))";
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
	
	    // Resetear estado completo — en este orden exacto
	    do remove_desire(predicate(DESEO_EXTINGUIR));
	    foco_asignado           <- nil;
	    estado_operativo        <- "Disponible";
	    refuerzos_pedidos       <- false;
	    retirada_notificada     <- false;
	    emergencia_notificada   <- false;
	    repostaje_notificado    <- false;
	    progreso_ultimo_reporte <- -1.0;
	}
}
