/**
* Name: Main Simulation
* Description: Inicialización y creación de agentes
*/
model GredosSimulation

import "parameters.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "agente_operativo.gaml"
import "recon_drone.gaml"
import "bombero_terrestre.gaml"
import "bombero_aereo.gaml"
import "coordinador.gaml"
import "metrics.gaml"

global {
    geometry shape <- envelope(dem_file);
    graph road_network;
    graph drivable_network; // Red transitable
    int burning_count <- 0;
	int burned_count  <- 0;

    init {
        write "Processing the map...";
        do create_gis_agents();
        do compute_spatial_relations();
        
        write "Initializing fire...";
        do ignite_fire();
        
        write "Loading completed";
    }

    // Initialization actions
    action create_gis_agents {
        create fuel_zone from: fuel_file with: [vegetation_type::read("DesTipEstr")];

        create road from: roads_file {
            list<point> pts     <- shape.points;
            list<point> new_pts <- [];
            loop pt over: pts {
                float z <- terrain_cell(pt).altitude + 2.0;
                new_pts <- new_pts + [{pt.x, pt.y, z}];
            }
            shape <- line(new_pts);
        }

        create water_point from: water_points_file {
            location <- {location.x, location.y, terrain_cell(location).altitude + 50.0};
        }

        create logistics_base from: base_file {
            location <- {location.x, location.y, terrain_cell(location).altitude + 20.0};
            
            // Creación de recursos vinculados a la posición física de la infraestructura base
            create bombero_terrestre number: firefighter_fleet_size {
                location <- myself.location;
            }
            
            create bombero_aereo number: aerial_firefighter_fleet_size {
                location <- {myself.location.x, myself.location.y, myself.location.z + 50.0};
            }
                
            if (is_centralized_model) {
                create coordinador number: 1 {
                    location <- {myself.location.x, myself.location.y, myself.location.z + 50.0};
                }
            }
        }
        
        // Despliegue estratégico aleatorio de la flota de drones
        create recon_drone number: drone_fleet_size {
            terrain_cell random_start_cell <- any(terrain_cell);
            float target_z <- random_start_cell.altitude + 100.0;
            location <- {random_start_cell.location.x, random_start_cell.location.y, target_z};
        }
    }

    action compute_spatial_relations {
        ask fuel_zone   { do assign_fuel_to_cells; }
        ask road        { do mark_cells; }
        ask water_point { do mark_cells; }

        list<geometry> road_geoms_2d <- (road as list) collect (line(each.shape.points collect ({each.x, each.y, 0.0})));
        // Limpiar el grafo para generar una red limpia
        list<geometry> clean_roads <- clean_network(road_geoms_2d, 3.0, true, true);
        
        road_network     <- as_edge_graph(clean_roads) with_shortest_path_algorithm #Dijkstra;
        drivable_network <- road_network;
    }

    action ignite_fire {
	    logistics_base base <- one_of(logistics_base);
	    float max_distance <- 4000.0; // radio máximo en metros desde la base
	
	    // Buscar celda con combustible alto dentro del radio
	    list<terrain_cell> candidates <- terrain_cell where (
	        each.fuel_factor > 0.0 and
	        !each.is_burned and
	        each distance_to base < max_distance
	    );
	
	    terrain_cell ignition_cell <- empty(candidates)
	        ? nil
	        : (candidates with_max_of (each.fuel_factor));
	
	    if (ignition_cell != nil) {
	        ask ignition_cell {
	            is_burning <- true;
	            color      <- COLOR_BURNING;
	            world.burning_count <- world.burning_count + 1;
	        }
	        write "Incendio iniciado en " + ignition_cell.location
	            + " (combustible: " + ignition_cell.fuel_factor
	            + ", distancia a base: " + int(ignition_cell distance_to base) + "m)";
	    } else {
	        write "No se encontró celda válida en radio de " + max_distance + "m. Ampliando búsqueda...";
	        // Fallback sin restricción de distancia
	        ignition_cell <- (terrain_cell where (each.fuel_factor > 0.0 and !each.is_burned))
	            with_max_of (each.fuel_factor);
	        if (ignition_cell != nil) {
	            ask ignition_cell { is_burning <- true; color <- COLOR_BURNING; world.burning_count <- world.burning_count + 1;}
	        }
	    }
	}
	
	reflex vary_wind when: every(50 #cycles) {
	    wind_direction <- wind_direction + rnd(-15.0, 15.0);
	    wind_intensity  <- max(0.5, min(5.0, wind_intensity + rnd(-0.3, 0.3)));
	}
}
