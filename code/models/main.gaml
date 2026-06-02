/**
* Name: Main Simulation
* Description: Entry point, initialization orchestration and GUI.
*/
model GredosSimulation

import "parameters.gaml"
import "environment.gaml"
import "infrastructure.gaml"

global {
    geometry shape <- envelope(dem_file);

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

		// Add the roads to the map according to the terrain elevation
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
        }
    }

    action compute_spatial_relations {
        ask fuel_zone   { do assign_fuel_to_cells; }
        ask road        { do mark_cells; }
        ask water_point { do mark_cells; }
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
        }
    }
}
