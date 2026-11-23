import { createClient } from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY || import.meta.env.VITE_SUPABASE_ANON_KEY;
export const configured=Boolean(url&&key&&!url.includes('YOUR_PROJECT'));
export const supabase=configured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:true}}):null;
export function assertReady(){if(!configured)throw new Error('Configure web/.env with your Supabase project URL and publishable key first.');}
export async function call(name,args={}){assertReady();const {data,error}=await supabase.rpc(name,args);if(error)throw Error(error.message);return data}
export async function get(table,columns='*',mod){assertReady();let q=supabase.from(table).select(columns);if(mod)q=mod(q);const {data,error}=await q;if(error)throw Error(error.message);return data||[]}
