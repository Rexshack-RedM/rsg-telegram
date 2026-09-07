/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  // The build is loaded from disk inside the RedM NUI browser (no HTTP server),
  // so every asset reference must be relative rather than root-absolute.
  assetPrefix: './',
  images: {
    unoptimized: true,
  },
};

export default nextConfig;
