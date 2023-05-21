use bytemuck::{ Pod, Zeroable };
use std::{borrow::Cow, io::Write, io::BufWriter};
use wgpu::util::DeviceExt;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct Colour {
    red: f32,
    green: f32,
    blue: f32
}

const IMAGE_WIDTH: usize = 1024;
const IMAGE_HEIGHT: usize = 512;

async fn run() {
    // bufer writes to stdout for performance
    let handle = &std::io::stdout();
    let mut buf = BufWriter::new(handle);

    writeln!(buf, "P3").unwrap();
    writeln!(buf, "{} {}", IMAGE_WIDTH, IMAGE_HEIGHT).unwrap();
    writeln!(buf, "255").unwrap();
    for value in execute_gpu::<Colour>().await.unwrap() {
        writeln!(buf, "{} {} {}", (value.red * 255.0) as u8, (value.green * 255.0) as u8, (value.blue * 255.0) as u8).unwrap();
    }

    buf.flush().unwrap();
}

async fn execute_gpu<Out: Pod>() -> Option<Vec<Out>> {
    let instance = wgpu::Instance::default();
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions::default())
        .await?;

    let (device, queue) = adapter
        .request_device(
            &wgpu::DeviceDescriptor {
                label: None,
                features: wgpu::Features::empty(),
                limits: wgpu::Limits::downlevel_defaults(),
            },
            None,
        )
        .await
        .unwrap();

    let info = adapter.get_info();
    // skip this on LavaPipe temporarily
    if info.vendor == 0x10005 {
        return None;
    }

    let cs_module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: None,
        source: wgpu::ShaderSource::Wgsl(Cow::Borrowed(include_str!("raytracer.wgsl"))),
    });

    eprintln!("Finished compiling shader");

    let output_size: u64 = (IMAGE_WIDTH * IMAGE_HEIGHT * std::mem::size_of::<Colour>()).try_into().unwrap();
    let output_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Output Buffer"),
        size: output_size,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });

    let staging_buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Staging Buffer"),
        size: output_size,
        usage: wgpu::BufferUsages::MAP_READ | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });

    let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("Bind Group Layout"),
        entries: &[
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { read_only: false },
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            },
        ],
    });

    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("Pipeline layout"),
        bind_group_layouts: &[&bind_group_layout],
        push_constant_ranges: &[],
    });

    let compute_pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("Compute pipeline"),
        layout: Some(&pipeline_layout),
        module: &cs_module,
        entry_point: "main",
    });

    for i in 0..IMAGE_WIDTH {
        let globals_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Globals Buffer"),
            contents: bytemuck::bytes_of(&(i as u32)),
            usage: wgpu::BufferUsages::UNIFORM
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("Bind group"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: output_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: globals_buffer.as_entire_binding(),
                }
            ],
        });

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
        {
            let mut cpass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor { label: None });
            cpass.set_pipeline(&compute_pipeline);
            cpass.set_bind_group(0, &bind_group, &[]);
            cpass.dispatch_workgroups(1, IMAGE_HEIGHT.try_into().unwrap(), 1);
        }
        queue.submit(Some(encoder.finish()));
    }

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
    encoder.copy_buffer_to_buffer(&output_buffer, 0, &staging_buffer, 0, output_size);

    queue.submit(Some(encoder.finish()));

    let buffer_slice = staging_buffer.slice(..);
    let (sender, receiver) = futures_intrusive::channel::shared::oneshot_channel();
    buffer_slice.map_async(wgpu::MapMode::Read, move |v| sender.send(v).unwrap());
    device.poll(wgpu::Maintain::Wait);

    receiver.receive().await.unwrap().unwrap();

    eprintln!("Finished compute shader");

    let result;
    {
        // With the current interface, we have to make sure all mapped views are
        // dropped before we unmap the buffer.
        let data = buffer_slice.get_mapped_range();
        result = bytemuck::cast_slice(&data).to_vec();
    }

    staging_buffer.unmap();
    Some(result)
}

fn main() {
    env_logger::init();
    pollster::block_on(run());
}
