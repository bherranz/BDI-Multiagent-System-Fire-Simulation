/**
* Name: Agente Dron de Reconocimiento
* Description: BDI cognitivo para la unidad aérea de vigilancia y detección.
*/

model GredosReconDrone

import "parameters.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "coordinador.gaml"
import "bombero_terrestre.gaml"
import "bombero_aereo.gaml"

species recon_drone control: simple_bdi skills: [moving] {

    // --- ATRIBUTOS ONTOLÓGICOS ---
    float nivel_bateria;
    float wind_tolerance <- drone_wind_tolerance;
    int patrol_waypoint_index <- 0;
    list<point> patrol_route <- [];
    int drone_index <- 0;

    // --- PREDICADOS BDI ---
    string BASE_BELIEF   <- "at_logistics_base";
    string PATROL_DESIRE <- "patrol_area";
    string REFUEL_DESIRE <- "recharge_battery";
    string VIGILAR_DESIRE <- "vigilar_zona";
	point zona_vigilada <- nil;
	int ciclos_vigilando <- 0;
	int max_ciclos_vigilancia <- 60;

    // --- ASPECTO VISUAL ---
    aspect default {
        draw line([{location.x, location.y, location.z},
                   {location.x, location.y, location.z - drone_altitude}])
             color: #red width: 1;
        draw circle(125.0) color: #cyan border: #darkblue;
    }

    // --- INICIALIZACIÓN ---
    init {
        speed <- drone_speed;
        drone_index <- int(self);
        // Escalonar la batería inicial para evitar que todos recarguen a la vez (Fix B1)
        nivel_bateria <- drone_max_fuel * (0.4 + rnd(0.6));
        do generate_patrol_route;
        do add_desire(predicate(PATROL_DESIRE));
    }

    // --- REFLEXES ---

    // Mantener altitud sobre el terreno
    reflex adjust_altitude_to_terrain {
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil) {
            float current_heading <- heading;
            location <- {location.x, location.y, current_cell.altitude + drone_altitude};
            heading  <- current_heading;
        }
    }

	reflex propagate_fire_knowledge when: !empty(get_beliefs_with_name("wildfire_detected")) and every(3 #cycles) {
	    list<recon_drone> drones_cercanos <- recon_drone at_distance 2000.0;
	    if (empty(drones_cercanos)) { return; }
	    list<predicate> mis_focos <- get_beliefs_with_name("wildfire_detected") collect (predicate(each));
	    
	    loop p over: drones_cercanos {
	        list<predicate> focos_nuevos <- [];
	        ask p {
	            focos_nuevos <- mis_focos where (!has_belief(each));
	        }
	        if (empty(focos_nuevos)) { continue; }
	        ask p {
	            loop pred_fuego over: focos_nuevos {
	                do add_belief(pred_fuego);
	                write "[GOSSIP] Dron [" + name + "] recibe creencia de fuego.";
	                
	                if (!is_centralized_model) {
	                    point fire_loc <- point(pred_fuego.values["location"]);
	                    bool already_covered <- (bombero_terrestre first_with (each.foco_asignado != nil and each.foco_asignado distance_to fire_loc < 150.0) != nil) or 
	                                            (bombero_aereo first_with (each.foco_asignado != nil and each.foco_asignado distance_to fire_loc < 150.0) != nil);
	                    
	                    if (!already_covered) {
	                        do trigger_reporting_protocol(fire_loc);
	                    }
	                }
	            }
	        }
	    }
	}

    // --- PLANES COGNITIVOS ---

    // PATRULLA
    plan patrol_area intention: predicate(PATROL_DESIRE) {

        // Batería baja → Protocolo 6
        if (nivel_bateria <= (drone_max_fuel * 0.2)) {
            string sector_id <- string(int(location.x / 1000.0)) + "_" + string(int(location.y / 1000.0));
            float battery_percent <- (nivel_bateria / drone_max_fuel) * 100.0;

            if (is_centralized_model) {
                write "[Protocolo 6] Inform(retiradaBateria(sector=" + sector_id + ", bateria=" + int(battery_percent) + "%)) → Coordinador";
                if (!empty(coordinador)) {
                    coordinador coord <- one_of(coordinador);
                    if ((self distance_to coord) <= coord.coverage_range) {
                        ask coord {
                            do receive_battery_alert(myself, sector_id, battery_percent);
                        }
                    } else {
                        write "Dron [" + name + "]: Fuera de rango. Retirando a base sin notificar.";
                    }
                }
            } else {
                // Protocolo 6 P2P: delegar ruta a dron cercano con batería suficiente
                write "[Protocolo 6 - P2P] Dron [" + name + "]: Broadcast de batería crítica a pares.";
                float broadcast_range <- 2500.0;
                list<recon_drone> nearby_drones <- recon_drone where (
                    each != self and
                    each distance_to self < broadcast_range and
                    each.nivel_bateria > (drone_max_fuel * 0.5)
                );
                if (!empty(nearby_drones)) {
                    recon_drone relief <- nearby_drones with_min_of (each distance_to self);
                    write "[Protocolo 6 - P2P] Dron [" + name + "]: Delegando ruta a [" + relief.name + "].";
                    ask relief {
                        do receive_sector_delegation(myself.patrol_route);
                    }
                } else {
                    write "[Protocolo 6 - P2P] Dron [" + name + "]: Ningún dron cercano disponible para el relevo.";
                }
            }

            do remove_desire(predicate(PATROL_DESIRE));
            do add_desire(predicate(REFUEL_DESIRE), 2.0);
            return;
        }

        // Suspender si viento demasiado fuerte
        if (wind_intensity > wind_tolerance) {
		    logistics_base base <- logistics_base with_min_of (each distance_to self);
		    float dist_base <- {location.x, location.y} distance_to {base.location.x, base.location.y};
		
		    if (dist_base > 50.0) {
		        if (!has_belief(predicate(BASE_BELIEF))) {
		            write "Dron [" + name + "]: Viento fuerte (" + wind_intensity +
		                  " m/s). Retirando a base.";
		            do add_belief(predicate(BASE_BELIEF));
		        }
		        do goto target: {base.location.x, base.location.y, location.z} speed: speed;
		        if (every(5 #cycles)) {
		            do scout_for_wildfire;
		        }
		
		    } else {
		        nivel_bateria <- nivel_bateria + 1.0;
		        if (every(10 #cycles)) {
		            write "Dron [" + name + "]: En tierra por viento (" + wind_intensity + " m/s).";
		        }
		    }
		    return;
		}
		if (has_belief(predicate(BASE_BELIEF))) {
		    write "Dron [" + name + "]: Viento normalizado (" + wind_intensity + 
		          " m/s). Reanudando patrulla.";
		    do remove_belief(predicate(BASE_BELIEF));
		}

        // Seguir los waypoints de la ruta de patrulla
        if (!empty(patrol_route) and patrol_waypoint_index < length(patrol_route)) {
            point target_waypoint <- patrol_route[patrol_waypoint_index];
            do goto target: {target_waypoint.x, target_waypoint.y, location.z} speed: speed;

            if ({location.x, location.y} distance_to target_waypoint < 50.0) {
                patrol_waypoint_index <- patrol_waypoint_index + 1;
                if (patrol_waypoint_index >= length(patrol_route)) {
                    patrol_waypoint_index <- 0; // Reiniciar ciclo de patrulla
                }
            }
        }

        nivel_bateria <- nivel_bateria - 1.0;

        // Escanear el entorno cada 5 ciclos durante la patrulla
        if (every(5 #cycles)) {
            do scout_for_wildfire;
        }
    }
    
    plan vigilar_zona intention: predicate(VIGILAR_DESIRE) {
	    if (zona_vigilada = nil) {
	        do remove_desire(predicate(VIGILAR_DESIRE));
	        return;
	    }
	
	    // Batería crítica, abandonar vigilancia
	    if (nivel_bateria <= (drone_max_fuel * 0.2)) {
	        write "Dron [" + name + "]: Batería crítica durante vigilancia. Retirando.";
	        zona_vigilada <- nil;
	        ciclos_vigilando <- 0;
	        do remove_desire(predicate(VIGILAR_DESIRE));
	        do add_desire(predicate(REFUEL_DESIRE), 2.0);
	        return;
	    }
	
	    // Orbitar alrededor de la zona vigilada
	    float orbit_radius <- drone_vision_range * 0.8;
	    float angle <- mod(cycle * 6.0, 360.0); // 6 grados por ciclo → vuelta completa en 60 ciclos
	    point orbit_point <- {
	        zona_vigilada.x + orbit_radius * cos(angle),
	        zona_vigilada.y + orbit_radius * sin(angle),
	        location.z
	    };
	    do goto target: orbit_point speed: speed * 0.7;
	    nivel_bateria <- nivel_bateria - 1.0;
	    ciclos_vigilando <- ciclos_vigilando + 1;
	
	    // Escanear cada 3 ciclos, más frecuente que en patrulla normal
	    if (every(3 #cycles)) {
	        do scout_for_wildfire;
	    }
	
	    // Comprobar si el foco ya se extinguió
	    geometry watch_zone <- circle(drone_vision_range) at_location zona_vigilada;
	    bool still_burning <- !empty((terrain_cell overlapping watch_zone) where (each.is_burning));
	
	    if (!still_burning or ciclos_vigilando >= max_ciclos_vigilancia) {
	        write "Dron [" + name + "]: Zona en " + zona_vigilada + " controlada. Reanudando patrulla.";
	        zona_vigilada <- nil;
	        ciclos_vigilando <- 0;
	        do remove_desire(predicate(VIGILAR_DESIRE));
	        do add_desire(predicate(PATROL_DESIRE));
	    }
	}

    // RECARGA DE BATERÍA
    plan recharge_battery intention: predicate(REFUEL_DESIRE) {
        logistics_base target_base <- logistics_base with_min_of (each distance_to self);
        if (target_base = nil) { return; }

        // Comprobación de capacidad de la base (Bug B2 — aplica en ambos modelos)
        list<recon_drone> drones_recargando <- recon_drone where (
            each != self and
            each distance_to target_base < 50.0 and
            !each.has_desire(predicate(PATROL_DESIRE))
        );
        if (length(drones_recargando) >= target_base.capacidad) {
            write "[Protocolo 6] Base llena (" + length(drones_recargando) + "/" + target_base.capacidad + " slots). Dron [" + name + "] en espera.";
            do goto target: {location.x + rnd(-80, 80), location.y + rnd(-80, 80), location.z} speed: speed * 0.3;
            return;
        }

        // Escanear también durante el vuelo de vuelta a base
        if (every(5 #cycles)) {
            do scout_for_wildfire;
        }

        do goto target: {target_base.location.x, target_base.location.y, location.z} speed: speed;

        point my_pos_2d   <- {location.x, location.y};
        point base_pos_2d <- {target_base.location.x, target_base.location.y};

        if (my_pos_2d distance_to base_pos_2d < 50.0) {
            nivel_bateria <- drone_max_fuel;
            write "Dron [" + name + "]: Batería recargada. Reanudando patrulla.";
            do remove_desire(predicate(REFUEL_DESIRE));
            do add_desire(predicate(PATROL_DESIRE));
        }
    }

    // --- ACCIONES ---

    // Generar ruta de patrulla por sectores divididos entre la flota
    action generate_patrol_route {
        float min_x <- 0.0;
        float max_x <- world.shape.width;
        float min_y <- 0.0;
        float max_y <- world.shape.height;

        float sector_width  <- (max_x - min_x) / float(drone_fleet_size);
        float sweep_spacing <- drone_vision_range * 1.5;

        int sector_index    <- int(self) mod drone_fleet_size;
        float sector_start_x <- min_x + (sector_index * sector_width);
        float sector_end_x   <- sector_start_x + sector_width;

        float offset_x   <- mod(sector_index, max(1, int(sector_width / sweep_spacing))) * sweep_spacing;
        float current_x  <- sector_start_x + offset_x;
        bool  sweep_up   <- (mod(sector_index, 2) = 0);

        patrol_route <- [];

        loop while: current_x < sector_end_x {
            if (sweep_up) {
                patrol_route <- patrol_route + [{current_x, min_y}];
                patrol_route <- patrol_route + [{current_x, max_y}];
            } else {
                patrol_route <- patrol_route + [{current_x, max_y}];
                patrol_route <- patrol_route + [{current_x, min_y}];
            }
            sweep_up  <- !sweep_up;
            current_x <- current_x + sweep_spacing;
        }
    }

    // Detectar incendios en el radio de visión y limpiar creencias obsoletas
    action scout_for_wildfire {
        geometry vision_area  <- circle(drone_vision_range) at_location {location.x, location.y};
        list<terrain_cell> visible_cells <- terrain_cell overlapping vision_area;
        list<terrain_cell> burning_cells <- visible_cells where (each.is_burning);

        // Clear extinguished fires from beliefs
        loop sb over: get_beliefs_with_name("wildfire_detected") {
            predicate pred <- predicate(sb);
            point believed_loc <- point(pred.values["location"]);
            terrain_cell believed_cell <- terrain_cell closest_to believed_loc;
            
            if (believed_cell != nil and !believed_cell.is_burning) {
                do remove_belief(pred);
            }
        }

        if (!empty(burning_cells)) {
            terrain_cell fire_focus <- burning_cells with_max_of (each.fuel_factor);
            predicate fire_belief <- predicate("wildfire_detected", ["location"::fire_focus.location]);

            if (!has_belief(fire_belief)) {
                do add_belief(fire_belief);
                write "[Protocol 1] Dron [" + name + "]: Fuego detectado en " + fire_focus.location;
                do trigger_reporting_protocol(fire_focus.location);
            }
        }
    }
    
    action relay_fire_alert(point fire_location, float fire_intensity, float fuel_available) {
	    write "Dron [" + name + "]: Reenviando alerta de foco en " + fire_location + " al coordinador.";
	    if (!empty(coordinador)) {
	        ask one_of(coordinador) {
	            do receive_fire_alert(myself, fire_location, fire_intensity, fuel_available);
	        }
	    }
	}

    // Protocolo 1 — Notificación de incendio
    action trigger_reporting_protocol(point fire_location) {
        terrain_cell fire_cell  <- terrain_cell closest_to fire_location;
        float fire_intensity    <- (fire_cell != nil) ? fire_cell.fuel_factor : 0.5;
        float fuel_available    <- (fire_cell != nil) ? fire_cell.fuel_factor : 0.0;
        total_focos_detectados <- total_focos_detectados + 1;

        if (is_centralized_model) {
		    write "[Protocolo 1] Inform(focoDetectado(pos=" + fire_location
		        + ", intensidad=" + fire_intensity
		        + ", combustible=" + fuel_available + ")) → Coordinador";
		    if (!empty(coordinador)) {
		        coordinador coord <- one_of(coordinador);
		        if ((self distance_to coord) <= coord.coverage_range) {
		            // En rango: notificar directamente
		            ask coord {
		                do receive_fire_alert(myself, fire_location, fire_intensity, fuel_available);
		            }
		        } else {
		            // Fuera de rango: buscar dron intermediario dentro del rango del coordinador
		            write "Dron [" + name + "]: Fuera de rango (" + int(self distance_to coord) + "m). Buscando intermediario...";
		            recon_drone relay <- recon_drone where (
		                each != self and
		                (each distance_to coord) <= coord.coverage_range
		            ) with_min_of (each distance_to self);
		
		            if (relay != nil) {
		                write "Dron [" + name + "]: Retransmitiendo via [" + relay.name + "].";
		                ask relay {
		                    do relay_fire_alert(fire_location, fire_intensity, fuel_available);
		                }
		            } else {
		                // Ningún intermediario disponible, el gossip propagará la creencia
		                // hasta que algún dron entre en rango en próximos ciclos
		                write "Dron [" + name + "]: Sin intermediarios en rango. Foco registrado localmente vía gossip.";
		            }
		        }
		    }
		    // Activar vigilancia de la zona tras reportar
			zona_vigilada <- fire_location;
			ciclos_vigilando <- 0;
			do remove_desire(predicate(PATROL_DESIRE));
			do add_desire(predicate(VIGILAR_DESIRE), 1.5);
		} else {
            // Anti-redundancia P2P: comprobar si algún agente ya tiene este foco asignado
            bool already_covered <-
                !(empty(bombero_terrestre where (each.foco_asignado != nil and each.foco_asignado distance_to fire_location < 150.0))) or
                !(empty(bombero_aereo     where (each.foco_asignado != nil and each.foco_asignado distance_to fire_location < 150.0)));

            if (already_covered) {
                write "[Protocolo 2 - CNP] Foco en " + fire_location + " ya cubierto. Ignorando.";
                return;
            }

            // --- CONTRACT NET PROTOCOL (Modelo Descentralizado) ---
            write "[Protocolo 2 - CNP] Dron [" + name + "]: CFP(proponerMision(" + fire_location + ")) → broadcast";
			// Activar vigilancia de la zona tras reportar
			zona_vigilada <- fire_location;
			ciclos_vigilando <- 0;
			do remove_desire(predicate(PATROL_DESIRE));
			do add_desire(predicate(VIGILAR_DESIRE), 1.5);
            // Fase 1: CFP, recoger pujas de todos los bomberos disponibles
            list<bombero_terrestre> all_ground <- bombero_terrestre where (each.estado_operativo = "Disponible");
            list<bombero_aereo>     all_aerial <- bombero_aereo     where (each.estado_operativo = "Disponible");

            map<agent, float> bids <- map([]);

            loop b over: all_ground {
                float bid <- 0.0;
                ask b { bid <- calcular_puja(fire_location); }
                if (bid < #max_float) {
                    bids[b] <- bid;
                    write "   Proponer [" + b.name + "]: coste=" + int(bid);
                }
            }
            loop b over: all_aerial {
                float bid <- 0.0;
                ask b { bid <- calcular_puja(fire_location); }
                if (bid < #max_float) {
                    bids[b] <- bid;
                    write "   Proponer [" + b.name + "]: coste=" + int(bid);
                }
            }

            // Fase 2: selección del ganador con menor coste
            if (empty(bids)) {
                write "[Protocolo 2 - CNP] Sin candidatos válidos para foco en " + fire_location;
            } else {
                agent winner <- bids.keys with_min_of (bids[each]);
                write "[Protocolo 2 - CNP] Ganador: [" + winner.name + "] con coste=" + int(bids[winner]);

                // Fase 3: Accept-Proposal al ganador, Reject-Proposal al resto
                if (winner is bombero_terrestre) {
                    ask bombero_terrestre(winner) {
                        write "Accept-Proposal(aceptarCompromiso(" + fire_location + ")) → [" + name + "]";
                        do request_mission(fire_location);
                    }
                } else if (winner is bombero_aereo) {
                    ask bombero_aereo(winner) {
                        write "Accept-Proposal(aceptarCompromiso(" + fire_location + ")) → [" + name + "]";
                        do request_mission(fire_location);
                    }
                }

                loop loser over: bids.keys where (each != winner) {
                    write "Reject-Proposal(aceptarCompromiso(" + fire_location + ")) → [" + loser.name + "]";
                }
            }
        }
    }

    // Protocolo 6: Asumir la ruta de un dron que se retira a recargar
    action receive_sector_delegation(list<point> orphaned_route) {
        loop pt over: orphaned_route {
            if (!(pt in patrol_route)) {
                patrol_route <- patrol_route + [pt];
            }
        }
        write "[Protocolo 6] Dron [" + name + "]: Sector huérfano asumido. Waypoints: " + length(patrol_route);
    }

    // Protocolo 9: Limpiar creencias al extinguirse un foco
    action receive_mission_completion(point extinguished_fire) {
        loop sb over: get_beliefs_with_name("wildfire_detected") {
            predicate pred <- predicate(sb);
            point believed_loc <- point(pred.values["location"]);
            if (believed_loc distance_to extinguished_fire < 150.0) {
                do remove_belief(pred);
                write "[Protocolo 9] Dron [" + name + "]: Foco " + extinguished_fire + " eliminado de memoria.";
            }
        }
    }
}
