const { colors } = require('./src/theme/tokens');

/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: 'media',
  // NativeWind scans these for class usage. `components/**` added for the
  // gluestack-ui component source that lives in-repo (shadcn-style copy-in).
  content: ['./App.tsx', './src/**/*.{js,jsx,ts,tsx}', './components/**/*.{js,jsx,ts,tsx}'],
  presets: [require('nativewind/preset')],
  // gluestack-ui components build class names from these semantic tokens at
  // runtime; safelist keeps them in the generated CSS even when not seen literally.
  safelist: [
    {
      pattern:
        /(bg|border|text|stroke|fill)-(foreground|card|popover|muted|destructive|border|input|ring|white|chart|sidebar|primary|secondary|typography|background|accent)(\/\d+)?$/,
    },
    {
      pattern:
        /(bg|border|text|stroke|fill)-(card|popover|muted|destructive|primary|secondary|accent|sidebar)-(foreground)(\/\d+)?$/,
    },
  ],
  theme: {
    extend: {
      // Semantic color tokens resolved from CSS vars set by GluestackUIProvider
      // (see components/ui/gluestack-ui-provider/config.ts).
      colors: {
        foreground: 'rgb(var(--foreground)/<alpha-value>)',
        card: {
          DEFAULT: 'rgb(var(--card) / <alpha-value>)',
          foreground: 'rgb(var(--card-foreground) / <alpha-value>)',
        },
        popover: {
          DEFAULT: 'rgb(var(--popover) / <alpha-value>)',
          foreground: 'rgb(var(--popover-foreground) / <alpha-value>)',
        },
        muted: {
          DEFAULT: 'rgb(var(--muted) / <alpha-value>)',
          foreground: 'rgb(var(--muted-foreground) / <alpha-value>)',
        },
        destructive: {
          DEFAULT: 'rgb(var(--destructive) / <alpha-value>)',
        },
        border: 'rgb(var(--border)/<alpha-value>)',
        input: 'rgb(var(--input)/<alpha-value>)',
        ring: 'rgb(var(--ring) / <alpha-value>)',
        white: 'rgb(255 255 255)',
        chart: {
          1: 'rgb(var(--chart-1) / <alpha-value>)',
          2: 'rgb(var(--chart-2) / <alpha-value>)',
          3: 'rgb(var(--chart-3) / <alpha-value>)',
          4: 'rgb(var(--chart-4) / <alpha-value>)',
          5: 'rgb(var(--chart-5) / <alpha-value>)',
        },
        sidebar: {
          'DEFAULT': 'rgb(var(--sidebar) / <alpha-value>)',
          'foreground': 'rgb(var(--sidebar-foreground) / <alpha-value>)',
          'primary': 'rgb(var(--sidebar-primary) / <alpha-value>)',
          'primary-foreground': 'rgb(var(--sidebar-primary-foreground) / <alpha-value>)',
          'accent': 'rgb(var(--sidebar-accent) / <alpha-value>)',
          'accent-foreground': 'rgb(var(--sidebar-accent-foreground) / <alpha-value>)',
          'border': 'rgb(var(--sidebar-border))',
          'ring': 'rgb(var(--sidebar-ring) / <alpha-value>)',
        },
        primary: {
          DEFAULT: 'rgb(var(--primary)/<alpha-value>)',
          foreground: 'rgb(var(--primary-foreground)/<alpha-value>)',
        },
        secondary: {
          DEFAULT: 'rgb(var(--secondary)/<alpha-value>)',
          foreground: 'rgb(var(--secondary-foreground)/<alpha-value>)',
        },
        typography: {
          white: '#FFFFFF',
          gray: '#D4D4D4',
          black: '#181718',
        },
        background: {
          DEFAULT: 'rgb(var(--background)/<alpha-value>)',
        },
        accent: {
          DEFAULT: 'rgb(var(--accent)/<alpha-value>)',
          foreground: 'rgb(var(--accent-foreground)/<alpha-value>)',
        },
        // App design tokens (single-sourced from src/theme/tokens.js). Prefixed
        // `app-` to avoid colliding with the gluestack semantic tokens above.
        // Utilities: `bg-app-*`, `text-app-*`, `border-app-*`.
        app: {
          'primary': colors.primary,
          'primary-light': colors.primaryLight,
          'background': colors.background,
          'surface': colors.surface,
          'surface-dark': colors.surfaceDark,
          'text-primary': colors.textPrimary,
          'text-secondary': colors.textSecondary,
          'text-secondary-mid': colors.textSecondaryMid,
          'text-secondary-strong': colors.textSecondaryStrong,
          'text-body': colors.textBody,
          'text-muted': colors.textMuted,
          'text-disabled': colors.textDisabled,
          'text-on-dark': colors.textOnDark,
          'border': colors.border,
          'border-strong': colors.borderStrong,
          'border-subtle': colors.borderSubtle,
          'chip-bg': colors.chipBg,
          'danger': colors.danger,
          'danger-strong': colors.dangerStrong,
          'danger-bg': colors.dangerBg,
          'success': colors.success,
          'warning': colors.warning,
          'warning-bg': colors.warningBg,
          'warning-bg-subtle': colors.warningBgSubtle,
          'warning-text': colors.warningText,
          'warning-text-soft': colors.warningTextSoft,
        },
      },
      fontFamily: {
        body: 'var(--font-sans)',
        mono: 'var(--font-mono)',
        sans: 'var(--font-sans)',
        serif: 'var(--font-serif)',
      },
      fontWeight: {
        extrablack: '950',
      },
      fontSize: {
        '2xs': '10px',
      },
      boxShadow: {
        'hard-1': '-2px 2px 8px 0px rgba(38, 38, 38, 0.20)',
        'hard-2': '0px 3px 10px 0px rgba(38, 38, 38, 0.20)',
        'hard-3': '2px 2px 8px 0px rgba(38, 38, 38, 0.20)',
        'hard-4': '0px -3px 10px 0px rgba(38, 38, 38, 0.20)',
        'hard-5': '0px 2px 10px 0px rgba(38, 38, 38, 0.10)',
        'soft-1': '0px 0px 10px rgba(38, 38, 38, 0.1)',
        'soft-2': '0px 0px 20px rgba(38, 38, 38, 0.2)',
        'soft-3': '0px 0px 30px rgba(38, 38, 38, 0.1)',
        'soft-4': '0px 0px 40px rgba(38, 38, 38, 0.1)',
      },
    },
  },
  plugins: [],
};
