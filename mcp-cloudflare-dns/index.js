#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';

const CLOUDFLARE_API_BASE = 'https://api.cloudflare.com/client/v4';

class CloudflareDNSServer {
  constructor() {
    this.server = new Server(
      {
        name: 'cloudflare-dns',
        version: '1.0.0',
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.apiToken = process.env.CLOUDFLARE_API_TOKEN;
    this.accountId = process.env.CLOUDFLARE_ACCOUNT_ID;

    if (!this.apiToken) {
      throw new Error('CLOUDFLARE_API_TOKEN environment variable is required');
    }

    this.setupHandlers();
    this.setupErrorHandling();
  }

  async makeCloudflareRequest(endpoint, method = 'GET', body = null) {
    const url = `${CLOUDFLARE_API_BASE}${endpoint}`;
    const headers = {
      'Authorization': `Bearer ${this.apiToken}`,
      'Content-Type': 'application/json',
    };

    const options = {
      method,
      headers,
    };

    if (body) {
      options.body = JSON.stringify(body);
    }

    const response = await fetch(url, options);
    const data = await response.json();

    if (!data.success) {
      throw new Error(`Cloudflare API Error: ${JSON.stringify(data.errors)}`);
    }

    return data.result;
  }

  setupErrorHandling() {
    this.server.onerror = (error) => {
      console.error('[MCP Error]', error);
    };

    process.on('SIGINT', async () => {
      await this.server.close();
      process.exit(0);
    });
  }

  setupHandlers() {
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: [
        {
          name: 'cloudflare_dns_list_zones',
          description: 'List all Cloudflare zones (domains)',
          inputSchema: {
            type: 'object',
            properties: {
              name: {
                type: 'string',
                description: 'Optional: Filter by zone name (e.g., "zenaflow.com")',
              },
            },
          },
        },
        {
          name: 'cloudflare_dns_list_records',
          description: 'List DNS records for a zone',
          inputSchema: {
            type: 'object',
            properties: {
              zone_id: {
                type: 'string',
                description: 'The Cloudflare zone ID',
              },
              type: {
                type: 'string',
                description: 'Optional: Filter by record type (A, AAAA, CNAME, MX, TXT, etc.)',
              },
              name: {
                type: 'string',
                description: 'Optional: Filter by record name (e.g., "subdomain.example.com")',
              },
            },
            required: ['zone_id'],
          },
        },
        {
          name: 'cloudflare_dns_create_record',
          description: 'Create a new DNS record',
          inputSchema: {
            type: 'object',
            properties: {
              zone_id: {
                type: 'string',
                description: 'The Cloudflare zone ID',
              },
              type: {
                type: 'string',
                description: 'Record type (A, AAAA, CNAME, MX, TXT, etc.)',
              },
              name: {
                type: 'string',
                description: 'DNS record name (e.g., "subdomain" or "subdomain.example.com")',
              },
              content: {
                type: 'string',
                description: 'Record content (IP address, domain, or text)',
              },
              ttl: {
                type: 'number',
                description: 'TTL in seconds (1 = automatic, default: 1)',
              },
              proxied: {
                type: 'boolean',
                description: 'Whether to proxy through Cloudflare (default: false)',
              },
              priority: {
                type: 'number',
                description: 'Priority (for MX records)',
              },
            },
            required: ['zone_id', 'type', 'name', 'content'],
          },
        },
        {
          name: 'cloudflare_dns_update_record',
          description: 'Update an existing DNS record',
          inputSchema: {
            type: 'object',
            properties: {
              zone_id: {
                type: 'string',
                description: 'The Cloudflare zone ID',
              },
              record_id: {
                type: 'string',
                description: 'The DNS record ID',
              },
              type: {
                type: 'string',
                description: 'Record type (A, AAAA, CNAME, MX, TXT, etc.)',
              },
              name: {
                type: 'string',
                description: 'DNS record name',
              },
              content: {
                type: 'string',
                description: 'New record content',
              },
              ttl: {
                type: 'number',
                description: 'TTL in seconds',
              },
              proxied: {
                type: 'boolean',
                description: 'Whether to proxy through Cloudflare',
              },
            },
            required: ['zone_id', 'record_id', 'type', 'name', 'content'],
          },
        },
        {
          name: 'cloudflare_dns_delete_record',
          description: 'Delete a DNS record',
          inputSchema: {
            type: 'object',
            properties: {
              zone_id: {
                type: 'string',
                description: 'The Cloudflare zone ID',
              },
              record_id: {
                type: 'string',
                description: 'The DNS record ID to delete',
              },
            },
            required: ['zone_id', 'record_id'],
          },
        },
      ],
    }));

    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;

      try {
        switch (name) {
          case 'cloudflare_dns_list_zones': {
            const queryParams = args.name ? `?name=${encodeURIComponent(args.name)}` : '';
            const zones = await this.makeCloudflareRequest(`/zones${queryParams}`);
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify(zones, null, 2),
                },
              ],
            };
          }

          case 'cloudflare_dns_list_records': {
            const params = new URLSearchParams();
            if (args.type) params.append('type', args.type);
            if (args.name) params.append('name', args.name);
            const queryString = params.toString() ? `?${params.toString()}` : '';

            const records = await this.makeCloudflareRequest(
              `/zones/${args.zone_id}/dns_records${queryString}`
            );
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify(records, null, 2),
                },
              ],
            };
          }

          case 'cloudflare_dns_create_record': {
            const recordData = {
              type: args.type,
              name: args.name,
              content: args.content,
              ttl: args.ttl || 1,
              proxied: args.proxied || false,
            };

            if (args.priority !== undefined) {
              recordData.priority = args.priority;
            }

            const result = await this.makeCloudflareRequest(
              `/zones/${args.zone_id}/dns_records`,
              'POST',
              recordData
            );
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify(result, null, 2),
                },
              ],
            };
          }

          case 'cloudflare_dns_update_record': {
            const recordData = {
              type: args.type,
              name: args.name,
              content: args.content,
              ttl: args.ttl || 1,
              proxied: args.proxied !== undefined ? args.proxied : false,
            };

            const result = await this.makeCloudflareRequest(
              `/zones/${args.zone_id}/dns_records/${args.record_id}`,
              'PUT',
              recordData
            );
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify(result, null, 2),
                },
              ],
            };
          }

          case 'cloudflare_dns_delete_record': {
            const result = await this.makeCloudflareRequest(
              `/zones/${args.zone_id}/dns_records/${args.record_id}`,
              'DELETE'
            );
            return {
              content: [
                {
                  type: 'text',
                  text: JSON.stringify({ success: true, deleted_record_id: args.record_id }, null, 2),
                },
              ],
            };
          }

          default:
            throw new Error(`Unknown tool: ${name}`);
        }
      } catch (error) {
        return {
          content: [
            {
              type: 'text',
              text: `Error: ${error.message}`,
            },
          ],
          isError: true,
        };
      }
    });
  }

  async run() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Cloudflare DNS MCP server running on stdio');
  }
}

const server = new CloudflareDNSServer();
server.run().catch(console.error);
