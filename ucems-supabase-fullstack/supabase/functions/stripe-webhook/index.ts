// Webhook must disable Supabase JWT verification, but verifies Stripe's signed RAW payload.
// Never fulfill an order based on the success redirect from the browser.
import { createClient } from 'npm:@supabase/supabase-js@2';
function hex(input:ArrayBuffer){return Array.from(new Uint8Array(input)).map(x=>x.toString(16).padStart(2,'0')).join('')}
function equalHex(a:string,b:string){if(a.length!==b.length)return false;let v=0;for(let i=0;i<a.length;i++)v|=a.charCodeAt(i)^b.charCodeAt(i);return v===0}
async function validSignature(body:string,header:string,secret:string){
  const parts=header.split(',').map(x=>x.trim());const timestamp=parts.find(x=>x.startsWith('t='))?.slice(2);
  const signatures=parts.filter(x=>x.startsWith('v1=')).map(x=>x.slice(3));
  const ts=Number(timestamp);
  if(!ts||Math.abs(Date.now()/1000-ts)>300||signatures.length===0)return false;
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  const expected=hex(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(`${timestamp}.${body}`)));
  return signatures.some(s=>equalHex(expected,s));
}
Deno.serve(async req=>{
  if(req.method!=='POST')return new Response('Method not allowed',{status:405});
  try{
    const body=await req.text();const signature=req.headers.get('stripe-signature')||'';
    const secret=Deno.env.get('STRIPE_WEBHOOK_SECRET');
    if(!secret||!await validSignature(body,signature,secret))return new Response('Invalid signature',{status:400});
    const event=JSON.parse(body);
    if(event.type==='checkout.session.completed'){
      const s=event.data.object;
      if(s.payment_status!=='paid') return new Response('Payment not complete',{status:200});
      if(!s.metadata?.order_id||!s.id||!Number.isInteger(s.amount_total)||!s.currency)throw new Error('Missing checkout fields');
      const admin=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
      const {error}=await admin.rpc('complete_checkout',{p_order:s.metadata.order_id,p_session:s.id,p_amount:s.amount_total,p_currency:s.currency});
      if(error)throw error;
    }
    return new Response('ok',{status:200});
  }catch(e){console.error('Stripe webhook error',e);return new Response('Webhook processing failed',{status:500})}
});
