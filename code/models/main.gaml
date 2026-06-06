/**
* Name: Main Simulation
* Description: Entry point, initialization orchestration and GUI.
*/
model GredosSimulation

import "parameters.gaml"
import "environment.gaml"
import "infrastructure.gaml"
import "recon_drone.gaml"
import "bombero_terrestre.gaml"
import "bombero_aereo.gaml"
import "coordinador.gaml"

global {
    geometry shape <- envelope(dem_file);
    graph road_network;

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
		    create bombero_terrestre number: firefighter_fleet_size {
		            location <- myself.location;
		        }
		    
		    create bombero_aereo number: aerial_firefighter_fleet_size {
		            location <- {myself.location.x, myself.location.y, myself.location.z + 50.0};
		        }
		        
		    if (is_centralized_model) {
		 		create coordinador number: 1 {
		 			location <- {myself.location.x, myself.location.y, myself.location.z + 50};
		 		}
		    }
        }

        
        // Drones are spawned across random locations on the map to maximize early fire detection coverage
        create recon_drone number: drone_fleet_size {
            // Pick any random cell from the terrain grid
            terrain_cell random_start_cell <- any(terrain_cell);
            // Position the drone floating 100 meters above that specific cell's elevation
            float target_z <- random_start_cell.altitude + 100.0;
            location <- {random_start_cell.location.x, random_start_cell.location.y, target_z};
        }
    }

    action compute_spatial_relations {
        ask fuel_zone   { do assign_fuel_to_cells; }
        ask road        { do mark_cells; }
        ask water_point { do mark_cells; }
        road_network <- as_edge_graph(road);
    }

    action ignite_fire {
        ask one_of(terrain_cell) {
            is_burning <- true;
            color      <- COLOR_BURNING;
        }
    }
}

// --- GRAPHICAL USER INTERFACE ---
experiment Fire_Simulation type: gui {
	parameter "Centralized Model" var: is_centralized_model category: "Agent Architecture";
	parameter "Scouting Drone Fleet Size"     var: drone_fleet_size min: 5 max: 20 category: "Agent Architecture";
	parameter "Ground Firefighter Fleet Size" var: firefighter_fleet_size min: 2 max: 10 category: "Agent Architecture";
	parameter "Aerial Firefighter Fleet Size" var: aerial_firefighter_fleet_size min: 1 max: 5 category: "Agent Architecture";
    parameter "Epsilon (uncertainty margin)"  var: epsilon_base       min: 0.0  max: 0.1   category: "Fire Model";
    parameter "Cell Burn Duration (Cycles)"   var: cell_burn_duration min: 5    max: 100   category: "Fire Model";
    parameter "Wind Direction (Degrees)"      var: wind_direction     min: 0.0  max: 360.0 category: "Wind Model";
    parameter "Wind Intensity"                var: wind_intensity     min: 0.5  max: 5.0   category: "Wind Model";
    parameter "Slope Influence Factor"        var: slope_influence_factor min: 0.001 max: 0.02 category: "Terrain Model";

    output {
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
