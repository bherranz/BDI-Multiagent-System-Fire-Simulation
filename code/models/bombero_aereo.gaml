/**
* Name: Agente Bombero Aéreo (Helicóptero)
* Description: BDI cognitivo para la unidad aérea.
* Hereda de agente_operativo.
*/

model GredosBomberoAereo

import "agente_operativo.gaml"
import "recon_drone.gaml"
import "coordinador.gaml"

species bombero_aereo parent: agente_operativo {

    // --- ATRIBUTOS ONTOLÓGICOS ESPECÍFICOS ---
    float nivel_combustible;
    float exposicion_viento <- 0.0;

    // --- PREDICADOS BDI ESPECÍFICOS ---
    string DESEO_REPOSTAR_COMBUSTIBLE <- "repostar_combustible";

    // --- VISUAL ASPECT ---
    aspect default {
        draw line([{location.x, location.y, location.z},
                   {location.x, location.y, location.z - 100.0}])
             color: #yellow width: 2;
        draw sphere(60.0) color: #yellow border: #orange;
    }

    // --- INITIALISATION ---
    init {
        speed <- aerial_firefighter_speed;
        carga_agua <- aerial_firefighter_max_water;
        nivel_combustible <- aerial_firefighter_max_fuel;
        radio_mision    <- 120.0;
    	prioridad_mision <- 4.5;
    	max_agua_mision  <- aerial_firefighter_max_water;
    }

    // --- COGNITIVE ACTIONS ---

    // Sobrescritura de la función virtual para el Protocolo 2
    action calcular_penalizacion_recursos type: float {
	    float penalizacion_agua <- (1.0 - (carga_agua / aerial_firefighter_max_water)) * 3000.0;
	    float penalizacion_fuel <- (1.0 - (nivel_combustible / aerial_firefighter_max_fuel)) * 8000.0;
	    float penalizacion_viento <- (wind_intensity > aerial_firefighter_wind_tolerance) ? #max_float : 0.0;
	    return penalizacion_agua + penalizacion_fuel + penalizacion_viento;
	}

    // Protocolo 2: Evaluación de misión y negociación BDI
    action puede_aceptar_mision type: bool {
	    float margen_agua   <- carga_agua - (aerial_firefighter_max_water * 0.15);
	    float margen_fuel   <- nivel_combustible - (aerial_firefighter_max_fuel * 0.25);
	    float margen_viento <- aerial_firefighter_wind_tolerance - wind_intensity;
	    if (!(margen_agua > 0 and margen_fuel > 0 and margen_viento > 0)) {
	        write "[Protocolo 2] Helicóptero [" + name + "]: REFUSE — (agua: " + int(carga_agua) + "L, fuel: " + int(nivel_combustible) + "L, viento: " + wind_intensity + ")";
	        return false;
	    }
	    return true;
	}

    // Protocolo 3: Informe de estado y progreso periódico optimizado
    action report_status_to_coordinator {
        geometry mission_zone <- circle(200.0) at_location foco_asignado;
        list<terrain_cell> nearby_fires <- (terrain_cell overlapping mission_zone) where (each.is_burning);
        
        string fire_state <- empty(nearby_fires) ? "controlado" : "activo";
        int current_fire_count <- length(nearby_fires);
        
        float progress <- (focos_iniciales > 0)
            ? max(0.0, min(100.0, (1.0 - (float(current_fire_count) / float(focos_iniciales))) * 100.0))
            : 100.0;
            
        if (abs(progress - progreso_ultimo_reporte) >= 5.0 or progress = 100.0) {
            progreso_ultimo_reporte <- progress;
            
            write "[Protocolo 3] Helicóptero [" + name + "]: Inform(focoActualizado(estado=" + fire_state
                + ", progreso=" + int(progress) + "%, agua=" + int(carga_agua) + "L, fuel=" + int(nivel_combustible) + "L))";
                
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_status_update(myself, myself.foco_asignado, fire_state, progress, myself.carga_agua, myself.nivel_combustible);
                }
            } else {
                float broadcast_range <- 800.0;
                list<bombero_terrestre> nearby_ground <- bombero_terrestre at_distance broadcast_range;
			    list<bombero_aereo> nearby_aerial <- (bombero_aereo at_distance broadcast_range) where (each != self);
                ask nearby_ground {
                    do recibir_broadcast_estado(myself.foco_asignado, fire_state, progress);
                }
                ask nearby_aerial { do recibir_broadcast_estado(myself.foco_asignado, fire_state, progress); }
            }
        }
    }

    // Protocolo 4: Petición de refuerzos (Aéreo)
    action request_reinforcements {
        if (refuerzos_pedidos) { return; }

        geometry search_zone <- circle(250.0) at_location {location.x, location.y};
        list<terrain_cell> nearby_fires <- (terrain_cell overlapping search_zone) where (each.is_burning);
        float fire_count <- float(length(nearby_fires));

        if (fire_count > 8.0) {
            write "[Protocolo 4] Helicóptero [" + name + "]: Request(ayudar(foco=" + foco_asignado + "))";
            
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_reinforcement_request(myself, myself.foco_asignado, fire_count);
                }
            } else {
                float broadcast_range <- 2000.0;
			    list<bombero_aereo>     nearby_aerial <- bombero_aereo at_distance broadcast_range;
			    list<bombero_terrestre> nearby_ground <- (bombero_terrestre at_distance broadcast_range) where (each != self);
			    list<bombero_terrestre> ground_disp <- nearby_ground where (each.estado_operativo = "Disponible");
			    list<bombero_aereo>     aerial_disp <- nearby_aerial where (each.estado_operativo = "Disponible");
			
			    if (!empty(ground_disp) or !empty(aerial_disp)) {
			        ask ground_disp { do request_mission(myself.foco_asignado); }
			        ask aerial_disp { do request_mission(myself.foco_asignado); }
			        write "📡 [Protocolo 4 - P2P] Refuerzo solicitado a " + 
			              length(ground_disp) + " terrestres y " + length(aerial_disp) + " aéreos disponibles.";
			    } else {
			        list<recon_drone> nearby_drones <- recon_drone at_distance broadcast_range;
			        if (!empty(nearby_drones)) {
			            ask nearby_drones {
			                predicate fire_belief <- predicate("wildfire_detected", ["location"::myself.foco_asignado]);
			                if (!has_belief(fire_belief)) {
			                    do add_belief(fire_belief);
			                    do trigger_reporting_protocol(myself.foco_asignado);
			                }
			            }
			            write "[Protocolo 4 - P2P] Sin unidades disponibles. Dron relanza CNP en zona.";
			        } else { write "[Protocolo 4 - P2P] Sin unidades ni drones en rango. Foco sin refuerzo."; }
			    }
            }
            refuerzos_pedidos <- true;
        }
    }
    
    // Protocolo 5: Notificación de retirada para recarga de agua
    action notify_water_withdrawal {
        if (foco_asignado != nil) {
            ask world { do log_msg("[Protocolo 5] Helicóptero [" + myself.name + "]: Inform(retiradaRecarga(foco=" + string(myself.foco_asignado) + "))"); }
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_withdrawal_notification(myself, myself.foco_asignado, "water_refill");
                }
            } else {
                float broadcast_range <- 1000.0;
				list<bombero_terrestre> nearby_ground <- bombero_terrestre at_distance broadcast_range;
			    list<bombero_aereo> nearby_aerial <- (bombero_aereo at_distance broadcast_range) where (each != self);
			    list<recon_drone> nearby_drones <- recon_drone at_distance broadcast_range;
                
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
				    write "[Protocolo 5 - P2P] Foco ya extinguido. No se envía relevo.";
				}
            }
        }
    }

    // Protocolo 7: Repostaje de combustible y delegación de foco
    action notify_fuel_refueling {
        if (foco_asignado != nil) {
            ask world { do log_msg("[Protocolo 7] Helicóptero [" + myself.name + "]: Inform(retiradaFuel(foco=" + string(myself.foco_asignado) + "))"); }
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_fuel_refuel_request(myself, myself.foco_asignado);
                }
            } else {
                float broadcast_range <- 1000.0;
				list<bombero_terrestre> nearby_ground <- bombero_terrestre at_distance broadcast_range;
			    list<bombero_aereo> nearby_aerial <- (bombero_aereo at_distance broadcast_range) where (each != self);
			    list<recon_drone> nearby_drones <- recon_drone at_distance broadcast_range;
                
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
				    write "[Protocolo 7 - P2P] Foco ya extinguido. No se envía relevo.";
				}
            }
        }
    }

    // Protocolo 8: Evacuación de emergencia
    action emergency_evacuation_protocol {
        ask world { do log_msg("[Protocolo 8] Helicóptero [" + myself.name + "]: Inform(retiradaEmergencia(condición_crítica))"); }
        estado_operativo <- "Retirada";
        total_evacuaciones <- total_evacuaciones + 1;
        if (foco_asignado != nil) {
            if (is_centralized_model) {
                ask one_of(coordinador) {
                    do receive_emergency_evacuation(myself, myself.foco_asignado, 0.0);
                }
            } else {
                float broadcast_range <- 1000.0;
				list<bombero_terrestre> nearby_ground <- bombero_terrestre at_distance broadcast_range;
			    list<bombero_aereo> nearby_aerial <- (bombero_aereo at_distance broadcast_range) where (each != self);
			    list<recon_drone> nearby_drones <- recon_drone at_distance broadcast_range;
                
                ask nearby_drones {
                    if (!(myself.foco_asignado in patrol_route)) {
                        patrol_route <- [myself.foco_asignado] + patrol_route;
                    }
                }
                ask nearby_aerial { do request_mission(myself.foco_asignado); }
                ask nearby_ground { do request_mission(myself.foco_asignado); }
            }
        }
    }

    // --- REFLEXES ---

    reflex adjust_altitude_to_terrain {
        terrain_cell current_cell <- terrain_cell(location);
        if (current_cell != nil) {
            float min_altitude <- current_cell.altitude + aerial_firefighter_cruise_altitude;
            location <- {location.x, location.y, min_altitude};
        }
    }

    reflex consume_fuel {
	    if (estado_operativo != "Disponible" and estado_operativo != "Repostando") {
	        float consumo <- (estado_operativo = "Retirada") ? 1.0 : 2.0;
	        nivel_combustible <- max(0.0, nivel_combustible - consumo);
	    }
	}

    reflex protocol_3_periodic_status when: (estado_operativo = "Extinguiendo" or estado_operativo = "En vuelo") 
    and foco_asignado != nil and every(15 #cycles) {
        do report_status_to_coordinator;
    }

    reflex protocol_4_check_reinforcements when: estado_operativo = "Extinguiendo" and (int(cycle) mod 20 = 0) {
	    refuerzos_pedidos <- false;
	    do request_reinforcements;
	}

    reflex wind_exposure_check {
        if (wind_intensity > aerial_firefighter_wind_tolerance) {
            exposicion_viento <- exposicion_viento + 1.0;
            if (exposicion_viento > 10.0 and !has_desire(predicate(DESEO_SUPERVIVENCIA))) {
			    estado_operativo <- "Retirada";
			    do remove_desire(predicate(DESEO_EXTINGUIR));
			    do remove_desire(predicate(DESEO_RECARGAR_AGUA));
			    do remove_desire(predicate(DESEO_REPOSTAR_COMBUSTIBLE));
			    do add_desire(predicate(DESEO_SUPERVIVENCIA), 5.5);
			    write "Helicóptero [" + name + "]: VIENTO CRÍTICO. Retirada táctica a base.";
			}
        } else {
            exposicion_viento <- max(0.0, exposicion_viento - 0.3);
        }
    }

    // Protocolos 5 y 7 unificados (Prioridad 5.0 y se borra la misión actual)
    reflex evaluate_resources when: !(estado_operativo in ["Recargando", "Repostando", "Retirada"]) {
        
        // Prioridad Máxima: Combustible
        if (nivel_combustible <= (aerial_firefighter_max_fuel * 0.25) and !has_desire(predicate(DESEO_REPOSTAR_COMBUSTIBLE))) {
            estado_operativo <- "Repostando";
            do remove_desire(predicate(DESEO_EXTINGUIR));
            // Si por algún motivo tenía deseo de agua, lo borramos para que no interfiera
            do remove_desire(predicate(DESEO_RECARGAR_AGUA)); 
            
            do add_desire(predicate(DESEO_REPOSTAR_COMBUSTIBLE), 6.0); 
            ask world { do log_msg("[Protocolo 7] Helicóptero [" + myself.name + "]: Combustible crítico (" + int(myself.nivel_combustible) + "L). Solicitando repostaje."); }
        }
        
        // Prioridad Secundaria: Agua
        else if (carga_agua <= (aerial_firefighter_max_water * 0.15) and !has_desire(predicate(DESEO_RECARGAR_AGUA))) {
            estado_operativo <- "Recargando";
            do remove_desire(predicate(DESEO_EXTINGUIR));
            do add_desire(predicate(DESEO_RECARGAR_AGUA), 5.0); 
            write "Helicóptero [" + name + "]: Agua crítica (" + int(carga_agua) + "L). Necesita recarga.";
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
        if (safe_zone != nil) {
            do goto target: {safe_zone.location.x, safe_zone.location.y, safe_zone.location.z + 50.0} speed: speed;
            
            if ({location.x, location.y} distance_to {safe_zone.location.x, safe_zone.location.y} < 100.0) {
	            if (wind_intensity <= aerial_firefighter_wind_tolerance) {
	                    exposicion_viento <- 0.0;
	                    estado_operativo <- "Disponible";
	                    emergencia_notificada <- false;
	                    do remove_desire(predicate(DESEO_SUPERVIVENCIA));
	                    write "Helicóptero [" + name + "]: Viento normalizado. A salvo en base y listo.";
	                } else {
	                    estado_operativo <- "Retirada";
	                    if (int(cycle) mod 20 = 0) {
	                        write "Helicóptero [" + name + "]: En base, protegido del viento (Viento: " + wind_intensity + ")";
	                    }
	                }
	               
	            }
	        }
	    }

    plan refuel_water intention: predicate(DESEO_RECARGAR_AGUA) {
        if (!retirada_notificada) {
            do notify_water_withdrawal;
            retirada_notificada <- true;
        }
        
        if (destino_recarga = nil) {
            water_point nearest_water <- water_point with_min_of (each distance_to self);
            if (nearest_water != nil) {
                destino_recarga <- {nearest_water.location.x, nearest_water.location.y, nearest_water.location.z + 50.0};
            }
        }

        // Viajar al destino
        if (destino_recarga != nil) {
            do goto target: destino_recarga speed: speed;
            
            if ({location.x, location.y} distance_to {destino_recarga.x, destino_recarga.y} < 80.0) {
                carga_agua <- aerial_firefighter_max_water;
                retirada_notificada <- false;
                destino_recarga <- nil;
                do remove_desire(predicate(DESEO_RECARGAR_AGUA));
                write "Helicóptero [" + name + "]: Carga de agua completada.";

                // Retomar misión de forma autónoma si el foco sigue activo
                if (foco_asignado != nil) {
                    geometry check_zone <- circle(120.0) at_location foco_asignado;
                    bool still_burning <- !empty((terrain_cell overlapping check_zone) where (each.is_burning));
                    
                    if (still_burning) {
                    	do remove_desire(predicate(DESEO_RECARGAR_AGUA));
                        estado_operativo <- "En vuelo";
                        focos_iniciales <- length((terrain_cell overlapping check_zone) where (each.is_burning));
                        do add_desire(predicate(DESEO_EXTINGUIR), 4.5);
                        ask world { do log_msg("Helicóptero [" + myself.name + "]: Retomando misión tras recarga de agua en " + string(myself.foco_asignado)); }
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

    plan refuel_fuel intention: predicate(DESEO_REPOSTAR_COMBUSTIBLE) {
	    if (!repostaje_notificado) {
	        do notify_fuel_refueling;
	        repostaje_notificado <- true;
	    }
	    
	    logistics_base target_base <- (destino_recarga = nil) 
	        ? logistics_base with_min_of (each distance_to self)
	        : logistics_base closest_to destino_recarga;

	    if (destino_recarga = nil and target_base != nil) {
	        destino_recarga <- {target_base.location.x, target_base.location.y, target_base.location.z + 50.0};
	    }
	    
		if (destino_recarga != nil and target_base != nil) {
	        // Comprobación de capacidad dinámica de slots usando el agente base
	        list<bombero_aereo> ocupantes <- bombero_aereo where ( 
	            each != self and  
	            each.estado_operativo = "Repostando" and 
	            each distance_to target_base < 100.0 
	        );
	        
	        if (length(ocupantes) >= target_base.capacidad) {
	            ask world { do log_msg("[Protocolo 7] Base llena (" + length(ocupantes) + "/" + target_base.capacidad + " slots). [" + myself.name + "] en patrón de espera."); }
	            do goto target: target_base.location speed: speed * 0.5;
	            return;
	        }
	        
			estado_operativo <- "Repostando";
	        do goto target: destino_recarga speed: speed;
	        
	        if ({location.x, location.y} distance_to {destino_recarga.x, destino_recarga.y} < 100.0) {
                nivel_combustible <- aerial_firefighter_max_fuel;
                repostaje_notificado <- false;
                destino_recarga <- nil;
                
                do remove_desire(predicate(DESEO_REPOSTAR_COMBUSTIBLE));
                ask world { do log_msg("Helicóptero [" + myself.name + "]: Repostaje de combustible completado."); }

                // Retomar misión de forma autónoma si el foco sigue activo
                if (foco_asignado != nil) {
                    geometry check_zone <- circle(120.0) at_location foco_asignado;
                    bool still_burning <- !empty((terrain_cell overlapping check_zone) where (each.is_burning));
                    
                    if (still_burning) {
                        estado_operativo <- "En vuelo";
                        focos_iniciales <- length((terrain_cell overlapping check_zone) where (each.is_burning));
                        do add_desire(predicate(DESEO_EXTINGUIR), 4.5);
                        ask world { do log_msg("Helicóptero [" + myself.name + "]: Retomando misión tras repostar combustible en " + string(myself.foco_asignado)); }
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

        estado_operativo <- "En vuelo";
        float distance_to_target <- {location.x, location.y} distance_to foco_asignado;
        float extinction_radius <- 120.0;
        
        if (distance_to_target > extinction_radius) {
            do goto target: {foco_asignado.x, foco_asignado.y, location.z} speed: speed;
        } else {
            estado_operativo <- "Extinguiendo";
            geometry extinction_zone <- circle(extinction_radius) at_location {location.x, location.y};
            list<terrain_cell> fires_to_extinguish <- (terrain_cell overlapping extinction_zone) where (each.is_burning);

            if (!empty(fires_to_extinguish)) {
                int fires_count <- 0;
                loop fire_cell over: fires_to_extinguish {
                    float water_use <- 8.0;
                    if (carga_agua >= water_use) {
                        carga_agua <- carga_agua - water_use;
                        total_agua_gastada <- total_agua_gastada + water_use;
                        fires_count <- fires_count + 1;
						ask fire_cell {
						    if (is_burning) {
						        is_burning <- false;
						        is_burned  <- true;
						        color      <- COLOR_BURNED;
						        burning_count <- burning_count - 1;
						        burned_count  <- burned_count + 1;
						    }
						}
                    }
                }
                if (fires_count > 0) {
                    write "Helicóptero [" + name + "]: Descarga apagó " + fires_count + " celdas. Agua: " + int(carga_agua) + "L";
                }
            } else {
                // Escaneo ampliado solo si el área inmediata está limpia
                geometry extended_search <- circle(250.0) at_location {location.x, location.y};
                list<terrain_cell> more_fires <- (terrain_cell overlapping extended_search)
        			where (each.is_burning and each.fuel_factor > 0.0);

                if (!empty(more_fires)) {
                    foco_asignado <- (more_fires with_min_of (each distance_to self)).location;
                    geometry new_zone <- circle(150.0) at_location foco_asignado;
                    focos_iniciales <- length((terrain_cell overlapping new_zone) where (each.is_burning));
                    write "Helicóptero [" + name + "]: Moviéndose al siguiente grupo de fuego en " + foco_asignado;
                } else {
                    write "Helicóptero [" + name + "]: Sector asegurado, no hay fuegos activos.";
                    do notify_mission_completion;
                }
            }
        }
    }
}