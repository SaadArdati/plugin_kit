// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightPageActions from 'starlight-page-actions';

// https://astro.build/config
export default defineConfig({
	site: 'https://plugin-kit.saad-ardati.dev',
	integrations: [
		starlight({
			title: 'Plugin Kit',
			description: 'A powerful, domain-agnostic plugin system for Dart applications.',
			logo: {
				src: './src/assets/logo.svg',
			},
			favicon: '/favicon.svg',
			head: [
				{
					tag: 'link',
					attrs: { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' },
				},
				{
					tag: 'link',
					attrs: { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32.png' },
				},
				{
					tag: 'meta',
					attrs: { property: 'og:image', content: '/og.png' },
				},
				{
					tag: 'meta',
					attrs: { name: 'twitter:image', content: '/og.png' },
				},
				{
					tag: 'meta',
					attrs: { name: 'twitter:card', content: 'summary_large_image' },
				},
			],
			social: [
				{
					icon: 'github',
					label: 'GitHub',
					href: 'https://github.com/SaadArdati/plugin_kit',
				},
			],
			customCss: ['./src/styles/custom.css'],
			plugins: [
				starlightPageActions({
					baseUrl: 'https://plugin-kit.saad-ardati.dev',
				}),
			],
			sidebar: [
				{
					label: 'Start Here',
					items: [
						{ label: 'Introduction', slug: 'introduction' },
						{ label: 'Why Plugin Kit?', slug: 'why-plugin-kit' },
						{ label: 'Getting Started', slug: 'getting-started' },
					],
				},
				{
					label: 'Core Concepts',
					items: [
						{ label: 'Concept Map', slug: 'concepts' },
						{ label: 'Plugins', slug: 'concepts/plugins' },
						{ label: 'Plugin Services', slug: 'concepts/plugin-services' },
						{ label: 'Service Registry', slug: 'concepts/service-registry' },
						{ label: 'Capabilities', slug: 'concepts/capabilities' },
						{ label: 'Configuration', slug: 'concepts/configuration' },
						{ label: 'Event Bus', slug: 'concepts/event-bus' },
						{ label: 'Event Patterns', slug: 'concepts/events' },
						{ label: 'Runtime', slug: 'concepts/runtime' },
						{ label: 'Sessions', slug: 'concepts/sessions' },
						{ label: 'Custom Contexts', slug: 'concepts/custom-context' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Guide Map', slug: 'guides' },
						{ label: 'Adding a Plugin', slug: 'guides/adding-a-plugin' },
						{ label: 'Flutter Integration', slug: 'guides/flutter-integration' },
						{ label: 'flutter_plugin_kit', slug: 'guides/flutter-plugin-kit' },
						{ label: 'Migrating a Flutter App', slug: 'guides/migrating-flutter-app' },
						{ label: 'Plugin Kit Dialog', slug: 'guides/plugin-kit-dialog' },
						{ label: 'Settings & Overrides', slug: 'guides/settings' },
						{ label: 'Logging', slug: 'guides/logging' },
						{ label: 'Testing', slug: 'guides/testing' },
					],
				},
				{
					label: 'Examples',
					items: [
						{ label: 'Examples Map', slug: 'examples' },
						{ label: 'The villain_lair scenarios', slug: 'examples/villain-lair' },
						{ label: 'The model_embassy tour', slug: 'examples/model-embassy' },
						{ label: 'The state_garden workshop', slug: 'examples/state-garden' },
						{ label: 'The code_editor architecture tour', slug: 'examples/code-editor' },
						{ label: 'The plugin_kit_dialog_demo showcase', slug: 'examples/plugin-kit-dialog-demo' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'Reference Map', slug: 'reference' },
						{ label: 'Plugins & Lifecycle', slug: 'reference/plugins-and-lifecycle' },
						{ label: 'Service Registry & Capabilities', slug: 'reference/service-registry-and-capabilities' },
						{ label: 'Event Bus & Events', slug: 'reference/event-bus-and-events' },
						{ label: 'Settings & Configuration', slug: 'reference/settings-and-configuration' },
						{ label: 'Dialog API', slug: 'reference/dialog-api' },
						{ label: 'State Management Bridges', slug: 'reference/state-management-bridges' },
						{ label: 'Naming Conventions', slug: 'reference/naming-conventions' },
						{ label: 'Architecture', slug: 'reference/architecture' },
					],
				},
				{ label: 'Troubleshooting', slug: 'troubleshooting' },
				{ label: 'FAQ', slug: 'faq' },
			],
		}),
	],
});
