#include "utils/main_util.cuh"

// Scene settings
int w = 224, h = 224 * 2;
int padding = 4; // Padding above rendered model

// Camera settings
const float focal_length = 2.16;
const float field_of_view = 0.7854; // 45 degrees
const V3f camera_position(0, 0, -100); // -100 for car

// Animation settings
bool animate = true;
constexpr int TARGET_FPS = 24;
constexpr int FRAME_TIME_MS = 1000 / TARGET_FPS;

// Rotation settings
bool rotate = true;
std::vector<V3f> rotations;
V3f rotation_increment(0, 0.05, 0);

// Lights
std::vector<V3f> light_positions;
std::vector<V4f> light_colors;

// Meshes
std::vector<Mesh> meshes;

void setup_scene(int argc, char* argv[]){
    load_meshes(argc, argv, meshes); // Load all meshes
    rotations.emplace_back(-0.05, 0.4, 0.05);
    if (meshes.size() > 0 && rotate) {
        for (auto r : rotations) meshes[0].triangles = rotate_mesh(meshes[0], r[0], r[1], r[2]); // Rotate mesh n
    }
    // Add light positions and colors
    light_colors.emplace_back(0.8f, 0.8f, 0.8f, 1.0f); // Light 1
    light_positions.emplace_back(0, 5, -30);
    light_colors.emplace_back(0.4f, 0.4f, 0.4f, 1.0f); // Light 2
    light_positions.emplace_back(10, -5, -20);
    light_colors.emplace_back(0.3f, 0.3f, 0.3f, 1.0f); // Light 3
    light_positions.emplace_back(10, 5, 20);
    light_colors.emplace_back(0.2f, 0.2f, 0.2f, 1.0f); // Light 4
    light_positions.emplace_back(-10, 20, -30);
}

void animate_main(){
    while (1) {
        auto start = std::chrono::high_resolution_clock::now();
        if (rotate && !meshes.empty()) {
            meshes[0].triangles = rotate_mesh(meshes[0], rotation_increment[0], rotation_increment[1], rotation_increment[2]);
        }
        float* output = h_raytrace(meshes, w, h, light_positions, light_colors, focal_length, field_of_view, camera_position);
        std::cout << "\033[H\033[J"; // Clear the screen
        print_scene_in_ascii(output, w, h, padding);
        delete[] output;
        auto end = std::chrono::high_resolution_clock::now();
        auto elapsed_time = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();
        if (elapsed_time < FRAME_TIME_MS) {
            std::this_thread::sleep_for(std::chrono::milliseconds(FRAME_TIME_MS - elapsed_time));
        }
    }
}

void photo_main(){
    auto start = std::chrono::high_resolution_clock::now();
    float* output = h_raytrace(meshes, w, h, light_positions, light_colors, focal_length, field_of_view, camera_position);
    std::cout << "\033[H\033[J"; 
    print_scene_in_ascii(output, w, h, padding);
    delete[] output;
    std::cout << "Runtime: " << std::chrono::duration<float>(std::chrono::high_resolution_clock::now() - start).count() << " seconds" << std::endl;
}

int main(int argc, char* argv[])
{
    warmup_cuda();
    setup_scene(argc, argv);
    if(animate){
        animate_main();
        return 0;
    }
    photo_main();
    return 0;
}
