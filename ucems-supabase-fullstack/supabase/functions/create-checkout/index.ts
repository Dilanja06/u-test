// Stripe TEST Checkout. Only the authenticated owner can initiate an owed payment.
import { createClient } from 'npm:@supabase/supabase-js@2';
const cors = { 'Access-Control-Allow-Origin': Deno.env.get('APP_URL') || 'http://localhost:5173', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
Deno.serve(async req => {
  if(req.method==='OPTIONS') return new Response('',{headers:cors});
  if(req.method!=='POST') return new Response('Method not allowed',{status:405,headers:cors});
  try{
    if(Deno.env.get('PAYMENT_PROVIDER')!=='stripe_connect_test') throw new Error('Paid checkout is disabled until a payment provider is configured');
    const secret = Deno.env.get('STRIPE_TEST_SECRET_KEY');
    if(!secret?.startsWith('sk_test_')) throw new Error('Stripe TEST secret key not configured; no live payments allowed');
    const bearer=req.headers.get('authorization')||'';
    if(!bearer.startsWith('Bearer ')) throw new Error('Sign in required');
    const url=Deno.env.get('SUPABASE_URL')!;
    const key=Deno.env.get('SUPABASE_ANON_KEY') || Deno.env.get('SUPABASE_PUBLISHABLE_KEY')!;
    const userClient=createClient(url,key,{global:{headers:{Authorization:bearer}}});
    const {data:{user},error:authErr}=await userClient.auth.getUser();
    if(authErr||!user) throw new Error('Invalid user session');
    const input=await req.json();
    if(!['membership','registration'].includes(input.kind)||typeof input.reference_id!=='string') throw new Error('Invalid purchase request');
    const {data:orders,error:orderErr}=await userClient.rpc('prepare_checkout',{p_kind:input.kind,p_reference:input.reference_id});
    if(orderErr||!orders?.[0]) throw new Error(orderErr?.message||'No payment due');
    const order=orders[0];
    const appUrl=Deno.env.get('APP_URL')||'http://localhost:5173';
    const params = new URLSearchParams({mode:'payment',success_url:appUrl+'/#/payments?success=1',cancel_url:appUrl+'/#/payments?cancelled=1',client_reference_id:order.order_id,'metadata[order_id]':order.order_id,'line_items[0][quantity]':'1','line_items[0][price_data][currency]':order.currency,'line_items[0][price_data][unit_amount]':String(order.amount_cents),'line_items[0][price_data][product_data][name]':String(order.label).slice(0,160)});
    const response=await fetch('https://api.stripe.com/v1/checkout/sessions',{method:'POST',headers:{Authorization:`Bearer ${secret}`,'Content-Type':'application/x-www-form-urlencoded'},body:params.toString()});
    const session=await response.json();
    if(!response.ok||!session.id||!session.url) throw new Error(session.error?.message||'Could not create checkout session');
    const service=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const {error:linkErr}=await service.rpc('link_checkout',{p_order:order.order_id,p_session:session.id});
    if(linkErr) throw new Error('Unable to bind checkout session');
    return Response.json({url:session.url},{headers:cors});
  }catch(e){return Response.json({error:(e as Error).message},{status:400,headers:cors})}
});
