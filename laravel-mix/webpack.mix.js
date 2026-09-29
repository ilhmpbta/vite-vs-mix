const mix = require('laravel-mix');
const path = require('path');

mix
    .postCss('resources/css/app.css', 'public/css', [
        require('@tailwindcss/postcss'),
        require('autoprefixer'),
    ])
    .webpackConfig({
        entry: { app: './resources/js/app.tsx' },
        module: {
            rules: [{
                test: /\.tsx?$/,
                exclude: /node_modules/,
                use: [{
                    loader: 'ts-loader',
                    options: {
                        transpileOnly: true,
                        configFile: 'tsconfig.json',
                        compilerOptions: { jsx: 'react-jsx' },
                    },
                }],
            }],
        },
        resolve: {
            alias: { '@': path.resolve(__dirname, 'resources/js') },
            extensions: ['.js', '.jsx', '.ts', '.tsx', '.json'],
        },
    })
    .options({ processCssUrls: false });