/**
* Name: Agente Bombero Terrestre
* Description: BDI cognitivo para la unidad operativa terrestre.
*/

model GredosBomberoTerrestre

import "parameters.gaml"
import "recon_drone.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "main.gaml"
import "agente_operativo.gaml"

species bombero_terrestre parent: agente_operativo {

    // --- ATRIBUTOS ONTOLÓGICOS ESPECÍFICOS ---
    float nivel_estres      <- 0.0;
    float nivel_cansancio   <- 0.0;
    path current_path <- nil;
    point last_destination <- nil;
    bool log_carretera <- false; // diagnóstico: avisa una vez al circular por carretera (borrable)

    // --- PREDICADOS BDI ESPECÍFICOS ---
    string DESEO_DESCANSAR <- "descansar_recuperar";

    // --- VISUAL ASPECT ---
    aspect default {
        draw box(80.0, 100.0, 60.0) color: #red border: #white;
    }

    // --- INITIALISATION ---
    init {
        speed <- firefighter_speed;
        carga_agua <- firefighter_max_water; 
    }

    // --- COGNITIVE ACTIONS ---

    // Sobrescritura de la función virtual para el Protocolo 2
    action calcular_penalizacion_recursos type: float {
	    float penalizacion_agua <- (1.0 - (carga_agua / firefighter_max_water)) * 5000.0;
	    float penalizacion_condicion <- (nivel_estres + nivel_cansancio) * 50.0;
	    return penalizacion_agua + penalizacion_condicion;
	}

    // Protocolo 2: Evaluación de misión y negociación BDI
    action puede_aceptar_mision type: bool {
	    float margen_estres <- firefighter_max_stress - nivel_estres;
	    float margen_agua   <- carga_agua - (firefighter_max_water * 0.15);
	    float margen_fatiga <- firefighter_max_fatigue - nivel_cansancio;
	    if (!(margen_agua > 0 and margen_estres > 10.0 and margen_fatiga > 10.0)) {
	        write "🔴 [Protocolo 2] Bombero [" + name + "]: REFUSE — (agua: " + int(carga_agua) + "L, estrés: " + int(nivel_estres) + ", fatiga: " + int(nivel_cansancio) + ")";
	        return false;
	    }
	    return true;
	}

    // Protocolo 3: Informe de estado y progreso periódico optimizado
    action report_status_to_coordinator {
        geometry mission_zone <- circle(150.0) at_location foco_asignado;
        list<terrain_cell> nearby_fires <- (terrain_cell overlapping mission_zone) where (each.is_burning);
        
        string fire_state <- empty(nearby_fires) ? "controlado" : "activo";
        int current_fire_count <- length(nearby_fires);

        float progress <- (focos_iniciales > 0)
            ? max(0.0, min(100.0, (1.0 - (float(current_fire_count) / float(focos_iniciales))) * 100.0))
            : 100.0;
            
        if (abs(progress - progreso_ultimo_reporte) >= 5.0 or progress = 100.0) {
            progreso_ultimo_reporte <- progress;
            
            write "📊 [Protocolo 3] Bombero [" + name + "]: Inform(focoActualizado(estado=" + fire_state
                + ", progreso=" + int(progress) + "%, agua=" + int(carga_agua) + "L, estrés=" + int(nivel_estres) + "))";
                
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_status_update(myself, myself.foco_asignado, fire_state, progress, myself.carga_agua, myself.nivel_estres);
                }
            } else {
                float broadcast_range <- 500.0;
                list<bombero_terrestre> nearby_peers <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                ask nearby_peers {
                    do recibir_broadcast_estado(myself.foco_asignado, fire_state, progress);
                }
            }
        }
    }

    // Protocolo 4: Petición de refuerzos
    action request_reinforcements {
        if (refuerzos_pedidos) { return; }

	    geometry search_zone <- circle(200.0) at_location {location.x, location.y};
	    list<terrain_cell> nearby_fires <- (terrain_cell overlapping search_zone) where (each.is_burning);
	    float fire_count <- float(length(nearby_fires));

        if (fire_count > 5.0) {
            write "⚠️ [Protocolo 4] Bombero [" + name + "]: Request(ayudar(foco=" + foco_asignado + "))";
            
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_reinforcement_request(myself, myself.foco_asignado, fire_count);
                }
            } else {
                float broadcast_range <- 500.0;
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each distance_to self < broadcast_range);
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                
                ask nearby_aerial { do request_mission(myself.foco_asignado); }
                ask nearby_ground { do request_mission(myself.foco_asignado); }
            }
            refuerzos_pedidos <- true;
        }
    }

    // Protocolo 5: Notificación de retirada para recargar agua
    action notify_water_withdrawal {
        if (foco_asignado != nil) {
            write "💧 [Protocolo 5] Bombero [" + name + "]: Inform(retiradaRecarga(foco=" + foco_asignado + "))";
            
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_withdrawal_notification(myself, myself.foco_asignado, "water_refill");
                }
            } else {
                float broadcast_range <- 600.0;
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each distance_to self < broadcast_range);
                list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < broadcast_range);
                
                ask nearby_drones {
                    if (!(myself.foco_asignado in patrol_route)) {
                        patrol_route <- [myself.foco_asignado] + patrol_route;
                    }
                }
                geometry target_zone <- circle(150.0) at_location foco_asignado;
				bool fire_still_active <- !empty((terrain_cell overlapping target_zone) where (each.is_burning));
				
				if (fire_still_active) {
				    ask nearby_ground { do request_mission(myself.foco_asignado); }
				    ask nearby_aerial { do request_mission(myself.foco_asignado); }
				} else {
				    write "ℹ️ [Protocolo 5 - P2P] Foco ya extinguido. No se envía relevo.";
				}
            }
        }
    }

    // Protocolo 8: Evacuación de emergencia
    action emergency_evacuation_protocol {
        write "🚨 [Protocolo 8] Bombero [" + name + "]: Inform(retiradaEmergencia(riesgo_crítico))";
        estado_operativo <- "Retirada";
        ask world { do registrar_evacuacion; }
        
        if (foco_asignado != nil) {
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_emergency_evacuation(myself, myself.foco_asignado, myself.nivel_estres);
                }
            } else {
                float broadcast_range <- 600.0;
                list<bombero_terrestre> nearby_ground <- bombero_terrestre where (each != self and each distance_to self < broadcast_range);
                list<bombero_aereo> nearby_aerial <- bombero_aereo where (each distance_to self < broadcast_range);
                list<recon_drone> nearby_drones <- recon_drone where (each distance_to self < broadcast_range);
                
                ask nearby_drones {
                    if (!(myself.foco_asignado in patrol_route)) {
                        patrol_route <- [myself.foco_asignado] + patrol_route;
                    }
                }
                ask nearby_ground { do request_mission(myself.foco_asignado); }
                ask nearby_aerial { do request_mission(myself.foco_asignado); }
            }
        }
    }

    // --- REFLEXES ---

    // Protocolo 3: Reportes periódicos de estado (Optimizado)
    reflex protocol_3_periodic_status when: estado_operativo = "Extinguiendo" and every(15 #cycles) {
        do report_status_to_coordinator;
    }

    // Protocolo 4: Detectar necesidad de refuerzos
    reflex protocol_4_check_reinforcements when: estado_operativo = "Extinguiendo" and (int(cycle) mod 20 = 0) {
	    refuerzos_pedidos <- false;
	    do request_reinforcements;
	}

    // Evaluate stress periodically instead of every cycle
    reflex evaluate_emotions when: (estado_operativo = "Extinguiendo" or estado_operativo = "Disponible") and every(5 #cycles) {
        geometry danger_zone <- circle(30.0) at_location {location.x, location.y};
        list<terrain_cell> nearby_fire <- (terrain_cell overlapping danger_zone) where (each.is_burning);

        if (!empty(nearby_fire)) {
            nivel_estres <- min(firefighter_max_stress, nivel_estres + (length(nearby_fire) * 0.5));
        } else {
            nivel_estres <- max(0.0, nivel_estres - 1.0);
        }

        if (estado_operativo != "Disponible") {
            nivel_cansancio <- min(firefighter_max_fatigue, nivel_cansancio + 0.1);
        }

        // Critical stress protocol
        if (nivel_estres > (firefighter_max_stress * 0.8) and !has_desire(predicate(DESEO_SUPERVIVENCIA))) {
            do add_desire(predicate(DESEO_SUPERVIVENCIA), 6.0);
            write "[Protocol 8] Bombero [" + name + "]: STRESS CRITICAL (" + int(nivel_estres) + "). Initiating retreat.";
        }

        // Critical water protocol
        if (carga_agua <= (firefighter_max_water * 0.15) and !has_desire(predicate(DESEO_RECARGAR_AGUA))) {
            estado_operativo <- "Recargando";
            do remove_desire(predicate(DESEO_EXTINGUIR)); 
            do add_desire(predicate(DESEO_RECARGAR_AGUA), 5.0); 
            write "[Protocol 5] Bombero [" + name + "]: Water critical (" + int(carga_agua) + "L). Heading to recharge.";
        }
    }

    // --- COGNITIVE PLANS ---

    plan tactical_retreat intention: predicate(DESEO_SUPERVIVENCIA) {
        if (!emergencia_notificada) {
            do emergency_evacuation_protocol;
            foco_asignado <- nil; 
            emergencia_notificada <- true;
        }

        logistics_base safe_zone <- logistics_base with_min_of (each distance_to self);
        do move_hybrid(safe_zone.location);

        if ({location.x, location.y} distance_to {safe_zone.location.x, safe_zone.location.y} < 50.0) {
            nivel_estres <- 0.0;
            estado_operativo <- "Disponible";
            emergencia_notificada <- false; 
            do remove_desire(predicate(DESEO_SUPERVIVENCIA));
            write "Bombero [" + name + "]: Reached safe zone. Stress normalised.";
        }
    }

    plan recharge_water intention: predicate(DESEO_RECARGAR_AGUA) {
    if (!retirada_notificada) {
        do notify_water_withdrawal;
        retirada_notificada <- true;
    }
    
    water_point nearest_water <- water_point with_min_of (each distance_to self);
    if (nearest_water != nil) {
        do move_hybrid(nearest_water.location);
        
        if ({location.x, location.y} distance_to {nearest_water.location.x, nearest_water.location.y} < 30.0) {
            carga_agua <- firefighter_max_water;
            retirada_notificada <- false;
            do remove_desire(predicate(DESEO_RECARGAR_AGUA));
            write "Bombero [" + name + "]: Depósito lleno.";
            
            // Retomar misión si el foco sigue activo
            if (foco_asignado != nil) {
                geometry check_zone <- circle(150.0) at_location foco_asignado;
                bool still_burning <- !empty((terrain_cell overlapping check_zone) where (each.is_burning));
                if (still_burning) {
                    estado_operativo <- "Extinguiendo";
                    focos_iniciales <- length((terrain_cell overlapping check_zone) where (each.is_burning));
                    do add_desire(predicate(DESEO_EXTINGUIR), 4.0);
                    write "Bombero [" + name + "]: Retomando misión en " + foco_asignado;
                } else {
                    foco_asignado <- nil;
                    estado_operativo <- "Disponible";
                }
            } else {
                estado_operativo <- "Disponible";
            }
        }
    }
}

    plan extinguish_fire intention: predicate(DESEO_EXTINGUIR) {
        if (foco_asignado = nil) {
            estado_operativo <- "Disponible";
            do remove_desire(predicate(DESEO_EXTINGUIR));
            return;
        }
    
        estado_operativo <- "Extinguiendo";
        float dist <- {location.x, location.y} distance_to {foco_asignado.x, foco_asignado.y};

        // --- MODE 1 & 2: MOVEMENT ---
        if (dist > 50.0) {
            do move_hybrid(foco_asignado);
            return;
        }
    
        // --- MODE 3: WITHIN EXTINCTION RADIUS (<50m) ---
        geometry extinction_zone <- circle(50.0) at_location {location.x, location.y};
        list<terrain_cell> fires_to_extinguish <- (terrain_cell overlapping extinction_zone) where (each.is_burning);
    
        if (!empty(fires_to_extinguish)) {
            loop fire_cell over: fires_to_extinguish {
                float water_use <- 8.0 * (1.0 + (nivel_estres / firefighter_max_stress * 0.5));
                if (carga_agua >= water_use) {
                    carga_agua <- carga_agua - water_use;
                    fire_cell.is_burning <- false;
                    fire_cell.is_burned  <- true;
                    fire_cell.color      <- COLOR_BURNED;
                }
            }
            write "Bombero [" + name + "]: Extinguishing. Water: " + int(carga_agua) + "L";
        } else {
		    geometry extended_search <- circle(250.0) at_location {location.x, location.y};
		    list<terrain_cell> more_fires <- (terrain_cell overlapping extended_search)
		        where (each.is_burning and each.fuel_factor > 0.0);
		    if (!empty(more_fires)) {
		        foco_asignado <- (more_fires with_min_of (each distance_to self)).location;
		        geometry new_zone <- circle(150.0) at_location foco_asignado;
		        focos_iniciales <- length((terrain_cell overlapping new_zone) where (each.is_burning));
		        write "Bombero [" + name + "]: Moving to next fire cluster at " + foco_asignado;
		    } else {
		        write "Bombero [" + name + "]: Sector secured.";
		        do notify_mission_completion;
		    }
		}
    }
    
    // Eleva al agente sobre la superficie del DEM para una visualización 3D correcta.
    action snap_to_terrain {
        terrain_cell tc <- terrain_cell(location);
        if (tc != nil) { location <- {location.x, location.y, tc.altitude + 2.0}; }
    }

    // Devuelve el nodo de la red TRANSITABLE (componente principal) más cercano al objetivo.
    // Al ser una componente conexa, siempre es alcanzable por carretera desde cualquier otro nodo.
    action road_access_point(point target_2d) type: point {
        if (drivable_network = nil or empty(drivable_network.vertices)) { return nil; }
        point n <- drivable_network.vertices closest_to target_2d;
        return (n = nil) ? nil : {n.x, n.y, 0.0};
    }

    action move_hybrid(point target_dest) {
        point loc_2d    <- {location.x, location.y, 0.0};
        point target_2d <- {target_dest.x, target_dest.y, 0.0};
        float dist_to_target <- loc_2d distance_to target_2d;
        if (dist_to_target < 5.0) { return; }

        bool  network_ok     <- (drivable_network != nil and !empty(drivable_network.edges));
        float walk_threshold <- 50.0; // el último tramo hasta el foco siempre es a pie

        // --- FASE A: NAVEGACIÓN POR CARRETERA (todo lo cerca que se pueda por carretera) ---
        // Solo conducimos si: estamos lejos, y la carretera nos deja MÁS cerca del foco
        // de lo que ya estamos a pie 
        if (network_ok and dist_to_target > walk_threshold) {
            point access <- road_access_point(target_2d);
            float access_to_target <- (access = nil) ? 1e9 : (access distance_to target_2d);

            if (access != nil and access_to_target < dist_to_target) {
			    // Comprobar si hay fuego inmediatamente adelante en la carretera
			    float ahead_dist <- min(60.0, dist_to_target * 0.1);
			    float angle_to_target <- location direction_to target_dest;
			    point ahead_point <- {
			        location.x + cos(angle_to_target) * ahead_dist,
			        location.y + sin(angle_to_target) * ahead_dist
			    };
			    geometry ahead_zone <- circle(25.0) at_location ahead_point;
			    list<terrain_cell> road_fires <- (terrain_cell overlapping ahead_zone) where (each.is_burning);
			
			    if (!empty(road_fires) and carga_agua > (firefighter_max_water * 0.2)) {
			        write "🔥➡️💧 Bombero [" + name + "]: Fuego en carretera, apagando paso.";
			        loop fire_cell over: road_fires {
			            float water_use <- 8.0 * (1.0 + (nivel_estres / firefighter_max_stress * 0.5));
			            if (carga_agua >= water_use) {
			                carga_agua           <- carga_agua - water_use;
			                fire_cell.is_burning <- false;
			                fire_cell.is_burned  <- true;
			                fire_cell.color      <- COLOR_BURNED;
			            }
			        }
			        do snap_to_terrain;
			        return;
			    }
			    location <- {location.x, location.y, 0.0};
                do goto target: target_2d on: drivable_network speed: speed * 1.2;
                do snap_to_terrain;

                if (!log_carretera) {
                    write "🛣️ Bombero [" + name + "]: circulando por carretera hacia el foco.";
                    log_carretera <- true;
                }
                return;
            }
        }

        // Al salir del modo carretera, invalidamos la ruta cacheada.
        last_destination <- nil;
        current_path     <- nil;

        // --- FASE B: A PIE (continúan andando: recta + evitación de fuego) ---
        float current_speed <- speed;
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil) {
            float slope_penalty <- (current_cell.altitude > 0) ? 0.8 : 1.0;
            float veg_penalty   <- (current_cell.fuel_factor > 0.05) ? 0.7 : 1.0;
            current_speed <- speed * slope_penalty * veg_penalty;
        }

        point normalized_dir <- {
            (target_dest.x - location.x) / dist_to_target,
            (target_dest.y - location.y) / dist_to_target
        };
        point next_location <- {
            location.x + (normalized_dir.x * current_speed),
            location.y + (normalized_dir.y * current_speed),
            location.z
        };

        // Protocolo de evitación táctica de celdas en llamas
		terrain_cell next_cell <- terrain_cell(next_location);
		if (next_cell != nil and next_cell.is_burning and dist_to_target > 60.0) {
		
		    // Intentar apagar el fuego que bloquea el paso antes de buscar desvío
		    if (carga_agua > (firefighter_max_water * 0.2)) {
		        geometry block_zone <- circle(30.0) at_location next_location;
		        list<terrain_cell> blocking_fires <- (terrain_cell overlapping block_zone) where (each.is_burning);
		
		        if (!empty(blocking_fires)) {
		            write "🔥➡️💧 Bombero [" + name + "]: Fuego en ruta, apagando paso antes de continuar.";
		            loop fire_cell over: blocking_fires {
		                float water_use <- 8.0 * (1.0 + (nivel_estres / firefighter_max_stress * 0.5));
		                if (carga_agua >= water_use) {
		                    carga_agua           <- carga_agua - water_use;
		                    fire_cell.is_burning <- false;
		                    fire_cell.is_burned  <- true;
		                    fire_cell.color      <- COLOR_BURNED;
		                }
		            }
		            do snap_to_terrain;
		            return; // Este ciclo apaga, el siguiente ya puede avanzar
		        }
		    }
		
		    // Sin agua suficiente o sin fuego apagable, buscar desvío
		    write "Bombero [" + name + "]: Fire in route, searching alternative.";
		    nivel_estres <- min(firefighter_max_stress, nivel_estres + 1.0);
		
		    bool found_path <- false;
		    loop offset over: [-45.0, 45.0, -90.0, 90.0] {
		        float base_angle <- location direction_to target_dest;
		        float new_angle  <- base_angle + offset;
		        point alt_loc <- {
		            location.x + cos(new_angle) * current_speed,
		            location.y + sin(new_angle) * current_speed,
		            location.z
		        };
		        terrain_cell alt_cell <- terrain_cell(alt_loc);
		        if (alt_cell != nil and !alt_cell.is_burning) {
		            location <- alt_loc;
		            found_path <- true;
		            break;
		        }
		    }
		    if (!found_path) { write "Bombero [" + name + "]: Surrounded by fire, waiting."; }
		
		    do snap_to_terrain;
		    return;
		}
		location <- next_location;
        do snap_to_terrain;
    }
}
