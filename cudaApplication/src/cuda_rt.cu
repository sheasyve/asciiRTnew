#include "cuda_rt.cuh"
#include "shapes/triangle.cuh"
#include "utils/ray.cuh"
#include "shapes/mesh.cuh"

__global__ void d_raytrace(
    Ray* rays, Triangle* triangles,
    int num_triangles, double* output,
    Eigen::Vector3d* light_positions,
    Eigen::Vector4d* light_colors, int num_lights
) {
    int x = blockIdx.x;
    int y = blockIdx.y;
    int width = gridDim.x;
    int idx = y * width + x;//Get index from pixel x and y
    if (idx >= width * gridDim.y) return;//Grid bounds check

    Ray r = rays[idx];
    double min_t = 1e20;
    int min_index = -1;

    for (int i = 0; i < num_triangles; i++) {//Closest Intersection
        double t = triangles[i].intersects(r);
        if (t > 0 && t < min_t) {
            min_t = t;
            min_index = i;
        }
    }
    if (min_index == -1) {
        output[idx] = 0.0;
        return;
    }

    Eigen::Vector3d p = r.origin + r.direction * min_t;
    Triangle closest = triangles[min_index];
    Eigen::Vector3d N = closest.normal();
    N.normalize();
    Eigen::Vector3d V = -r.direction;
    V.normalize();

    double brightness = 0.005;//Start with ambient light
    double diffuse_intensity = 0.4;
    double specular_intensity = 0.4;
    double shine = 32.0;
  
    for (int i = 0; i < num_lights; i++) {//Add light from each source
        Eigen::Vector3d L = (light_positions[i] - p);
        double d = L.norm();
        L.normalize();
        Eigen::Vector3d light_rgb = light_colors[i].head<3>();
        double a=1.,b=.1,c=.01;
        double attenuation = 1./(a+b*d+c*d*d);//Distance dropoff
        //Diffuse
        double lambertian = N.dot(L);
        lambertian = fmax(lambertian, 0.0);
        brightness += attenuation * diffuse_intensity * lambertian * light_rgb.norm();
        //Specular
        Eigen::Vector3d R = (2.0 * N.dot(L) * N - L).normalized();
        double spec_angle = R.dot(V);
        spec_angle = fmax(spec_angle, 0.0);
        double specular = pow(spec_angle, shine);
        brightness += attenuation * specular_intensity * specular * light_rgb.norm();
        brightness = fmin(brightness, 1.0);
    }
    output[idx] = fmin(brightness, 1.0);
}

double* h_raytrace(
    Ray* rays, Mesh mesh,
    int width, int height,
    std::vector<Eigen::Vector3d> light_positions,
    std::vector<Eigen::Vector4d> light_colors,
    double rX, double rY, double rZ
) {
    int size = width * height;
    int num_triangles = mesh.triangles.size();
    int num_lights = light_positions.size();

    double* h_output = new double[size];

    Ray* d_rays = nullptr;
    Triangle* d_triangles = nullptr;
    double* d_output = nullptr;
    Eigen::Vector3d* d_lights = nullptr;
    Eigen::Vector4d* d_light_colors = nullptr;

    //Rotation, should move this to a function in main or ideally it's own. CUDA kernel before this one. but this works for now
    Eigen::Matrix3d rotMatX;
    rotMatX = Eigen::AngleAxisd(rX, Eigen::Vector3d::UnitX());
    Eigen::Matrix3d rotMatY;
    rotMatY = Eigen::AngleAxisd(rY, Eigen::Vector3d::UnitY());
    Eigen::Matrix3d rotMatZ;
    rotMatZ = Eigen::AngleAxisd(rZ, Eigen::Vector3d::UnitZ());
    Eigen::Matrix3d rotationMatrix = rotMatZ * rotMatY * rotMatX;
    std::vector<Triangle> rotated_triangles = mesh.triangles;
    for (auto& tri : rotated_triangles) {
        tri.p1 = rotationMatrix * tri.p1;
        tri.p2 = rotationMatrix * tri.p2;
        tri.p3 = rotationMatrix * tri.p3;
    }

    cudaMalloc((void**)&d_rays, size * sizeof(Ray));
    cudaMalloc((void**)&d_triangles, num_triangles * sizeof(Triangle));
    cudaMalloc((void**)&d_output, size * sizeof(double));
    cudaMalloc((void**)&d_lights, num_lights * sizeof(Eigen::Vector3d));
    cudaMalloc((void**)&d_light_colors, num_lights * sizeof(Eigen::Vector4d));

    cudaMemcpy(d_rays, rays, size * sizeof(Ray), cudaMemcpyHostToDevice);
    cudaMemcpy(d_triangles, rotated_triangles.data(), num_triangles * sizeof(Triangle), cudaMemcpyHostToDevice);
    cudaMemcpy(d_lights, light_positions.data(), num_lights * sizeof(Eigen::Vector3d), cudaMemcpyHostToDevice);
    cudaMemcpy(d_light_colors, light_colors.data(), num_lights * sizeof(Eigen::Vector4d), cudaMemcpyHostToDevice);

    dim3 gridDim(width, height);
    d_raytrace<<<gridDim, 1>>>(d_rays, d_triangles, num_triangles, d_output, d_lights, d_light_colors, num_lights);

    cudaMemcpy(h_output, d_output, size * sizeof(double), cudaMemcpyDeviceToHost);

    cudaFree(d_rays);
    cudaFree(d_triangles);
    cudaFree(d_output);
    cudaFree(d_lights);
    cudaFree(d_light_colors);

    return h_output;
}
