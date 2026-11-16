import {readFileSync} from 'node:fs';
import {before, after, beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, getDoc, getDocs, collection, query, where, setDoc, updateDoc, writeBatch, runTransaction, serverTimestamp, Timestamp} from 'firebase/firestore';

let env;
const code = 'a'.repeat(32), ownerCode = 'o'.repeat(32);
const newGroup = () => ({name:'Kona', createdBy:'owner', createdAt:serverTimestamp(),
  timeZone:'America/Vancouver', activeTripId:null, lastOdometer:null, schedule:{},
  spliitGroupId:'',spliitName:'',spliitMembers:[],spliitMemberIds:[],ownerMemberId:''});
before(async () => {
  env = await initializeTestEnvironment({projectId:'demo-kona-share', firestore:{
    host:'127.0.0.1',port:8080,rules:readFileSync(new URL('../firestore.rules',import.meta.url),'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async c => {
    const db = c.firestore();
    await setDoc(doc(db,'groups/g'),newGroup());
    for (const [uid,role] of [['owner','owner'],['owner2','owner'],['borrower','borrower']]) {
      await setDoc(doc(db,`groups/g/members/${uid}`),{uid,name:uid,role,spliitMemberId:''});
      await setDoc(doc(db,`users/${uid}`),{name:uid,groupId:'g'});
    }
    await setDoc(doc(db,`invites/${code}`),{groupId:'g',role:'borrower'});
    await setDoc(doc(db,`invites/${ownerCode}`),{groupId:'g',role:'owner'});
    await setDoc(doc(db,'groups/g/private/invites'),{ownerCode,borrowerCode:code});
    const at = Date.now()+3600000;
    for (const id of ['a','b']) await setDoc(doc(db,`groups/g/bookings/${id}`),{
      userId:'borrower',driver:'borrower',startAt:Timestamp.fromMillis(at),endAt:Timestamp.fromMillis(at+7200000),
      estimatedKm:30,note:'Errands',status:'requested',decisionNote:'',createdAt:Timestamp.now()});
  });
});
const dbFor = uid => env.authenticatedContext(uid).firestore();
test('nonmembers cannot read groups, members or trips',async () => {
  const db = dbFor('stranger');
  await assertFails(getDoc(doc(db,'groups/g')));
  await assertFails(getDoc(doc(db,'groups/g/members/owner')));
  await assertFails(getDoc(doc(db,'groups/g/trips/private')));
});
test('borrowers cannot promote themselves, change rates/config, or approve',async () => {
  const db = dbFor('borrower');
  await assertFails(updateDoc(doc(db,'groups/g/members/borrower'),{role:'owner'}));
  await assertFails(updateDoc(doc(db,'groups/g'),{spliitGroupId:'stolen'}));
  await assertFails(updateDoc(doc(db,'groups/g/bookings/a'),{status:'approved'}));
  await assertFails(getDoc(doc(db,'groups/g/private/invites')));
});
test('borrowers cannot mint owner invitations',async () => {
  await assertFails(setDoc(doc(dbFor('borrower'),`invites/${'x'.repeat(32)}`),{groupId:'g',role:'owner'}));
});
test('borrower invite cannot grant owner role; valid borrower join succeeds',async () => {
  const db = dbFor('new');
  await setDoc(doc(db,'users/new'),{name:'New',groupId:null});
  function join(role) {
    const batch = writeBatch(db);
    batch.set(doc(db,'joinProofs/new'),{groupId:'g',code});
    batch.set(doc(db,'groups/g/members/new'),{uid:'new',name:'New',role,spliitMemberId:''});
    batch.update(doc(db,'users/new'),{groupId:'g'});
    return batch.commit();
  }
  await assertFails(join('owner'));
  await assertSucceeds(join('borrower'));
});
test('an owner invitation grants owner role',async () => {
  const db = dbFor('newowner');
  await setDoc(doc(db,'users/newowner'),{name:'New owner',groupId:null});
  const batch = writeBatch(db);
  batch.set(doc(db,'joinProofs/newowner'),{groupId:'g',code:ownerCode});
  batch.update(doc(db,'groups/g'),{ownerRosterVersion:1});
  batch.set(doc(db,'groups/g/members/newowner'),{uid:'newowner',name:'New owner',role:'owner',spliitMemberId:''});
  batch.update(doc(db,'users/newowner'),{groupId:'g'});
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDoc(doc(db,'groups/g/private/invites')));
});
test('new group creator becomes owner atomically',async () => {
  const db = dbFor('creator');
  await setDoc(doc(db,'users/creator'),{name:'Creator',groupId:null});
  const batch = writeBatch(db);
  batch.set(doc(db,'groups/new'),{...newGroup(),createdBy:'creator'});
  batch.set(doc(db,'groups/new/members/creator'),{uid:'creator',name:'Creator',role:'owner',spliitMemberId:''});
  batch.update(doc(db,'users/creator'),{groupId:'new'});
  batch.set(doc(db,`invites/${'n'.repeat(32)}`),{groupId:'new',role:'owner'});
  batch.set(doc(db,'groups/new/private/invites'),{ownerCode:'n'.repeat(32),borrowerCode:'m'.repeat(32)});
  await assertSucceeds(batch.commit());
});
test('concurrent owner approvals cannot book the same time twice',async () => {
  async function approve(uid,id) {
    const db = dbFor(uid), g = doc(db,'groups/g'), b = doc(db,`groups/g/bookings/${id}`);
    return runTransaction(db,async tx => {
      const group = (await tx.get(g)).data(), booking = (await tx.get(b)).data();
      const schedule = {...group.schedule};
      const start=booking.startAt.toMillis(),end=booking.endAt.toMillis();
      for (const slot of Object.values(schedule)) {
        if (start < slot.end && end > slot.start) throw Error('overlap');
      }
      schedule[id]={start,end};tx.update(g,{schedule});tx.update(b,{status:'approved'});
    });
  }
  const results = await Promise.allSettled([approve('owner','a'),approve('owner2','b')]);
  assert.equal(results.filter(r => r.status==='fulfilled').length,1);
  assert.equal(results.filter(r => r.status==='rejected').length,1);
});
test('new trip ignores the previous odometer but ending readings cannot go below its own start',async () => {
  await env.withSecurityRulesDisabled(async c => { await updateDoc(doc(c.firestore(),'groups/g/bookings/a'), {status:'approved',startAt:Timestamp.fromMillis(Date.now()-60000)}); await updateDoc(doc(c.firestore(),'groups/g'),{lastOdometer:900000}); });
  const db = dbFor('borrower');
  const batch = writeBatch(db);
  batch.set(doc(db,'groups/g/trips/t'),{userId:'borrower',driver:'borrower',bookingId:'a',
    startAt:serverTimestamp(),startKm:42000,endAt:null,endKm:null,status:'active',sync:'local',expenseId:'',remoteGroupId:'',payerId:'',borrowerId:''});
  batch.update(doc(db,'groups/g/bookings/a'),{status:'active'});
  batch.update(doc(db,'groups/g'),{activeTripId:'t'});
  await assertSucceeds(batch.commit());
  const finish = km => {
    const b=writeBatch(db);
    b.update(doc(db,'groups/g/trips/t'),{status:'completed',endAt:Timestamp.now(),endKm:km});
    b.update(doc(db,'groups/g/bookings/a'),{status:'completed'});
    b.update(doc(db,'groups/g'),{activeTripId:null,lastOdometer:km,schedule:{}});
    return b.commit();
  };
  await assertFails(finish(41999));
  await assertSucceeds(finish(42030));
  await assertFails(updateDoc(doc(db,'groups/g/trips/t'),{startKm:0}));
});

test('Spliit participants cannot be stolen or set to the owner payer', async () => {
  await updateDoc(doc(dbFor('owner'),'groups/g'),{
    spliitGroupId:'remote',spliitName:'Our group',ownerMemberId:'payer',
    spliitMembers:[{id:'payer',name:'Owners'},{id:'alex',name:'Alex'},{id:'sam',name:'Sam'}],
    spliitMemberIds:['payer','alex','sam']});
  const db = dbFor('borrower');
  const claim = (remoteId, user='borrower') => {
    const db = dbFor(user), b=writeBatch(db);
    b.set(doc(db,`groups/g/spliitClaims/${remoteId}`),{uid:user});
    b.update(doc(db,`groups/g/members/${user}`),{spliitMemberId:remoteId});
    return b.commit();
  };
  await assertFails(claim('payer'));
  await assertSucceeds(claim('alex'));
  await assertFails(claim('alex','owner2'));
  await assertFails(updateDoc(doc(db,'groups/g/members/borrower'),{spliitMemberId:'sam'}));
});


async function beginEarlyTrip(startsInMs, {expired=false, suppliedStart=null}={}) {
  const start=Timestamp.fromMillis(Date.now()+startsInMs);
  await env.withSecurityRulesDisabled(async c=>{
    await updateDoc(doc(c.firestore(),'groups/g/bookings/a'),{status:'approved',startAt:start,endAt:Timestamp.fromMillis(expired ? Date.now()-60000 : start.toMillis()+7200000)});
  });
  const db=dbFor('borrower'),b=writeBatch(db);
  b.set(doc(db,'groups/g/trips/early'),{userId:'borrower',driver:'borrower',bookingId:'a',startAt:suppliedStart??serverTimestamp(),startKm:42000,endAt:null,endKm:null,status:'active',sync:'local',expenseId:'',remoteGroupId:'',payerId:'',borrowerId:''});
  b.update(doc(db,'groups/g/bookings/a'),{status:'active'});
  b.update(doc(db,'groups/g'),{activeTripId:'early'});
  return b.commit();
}
test('a borrower can start 30 minutes early with the actual server time',async()=>{
  const before=Date.now();await assertSucceeds(beginEarlyTrip(1800000));
  const db=dbFor('borrower'),trip=(await getDoc(doc(db,'groups/g/trips/early'))).data();
  const booking=(await getDoc(doc(db,'groups/g/bookings/a'))).data();
  assert.ok(trip.startAt.toMillis()>=before);assert.ok(trip.startAt.toMillis()<=Date.now());
  assert.ok(trip.startAt.toMillis()<booking.startAt.toMillis());
});
test('a borrower can start exactly one hour early',async()=>{
  await assertSucceeds(beginEarlyTrip(3600000));
});
test('starting more than one hour early or after the booked return is refused',async()=>{
  await assertFails(beginEarlyTrip(3660000));
  await assertFails(beginEarlyTrip(-7200000,{expired:true}));
});
test('an early start cannot substitute a planned or backdated start time',async()=>{
  await assertFails(beginEarlyTrip(1800000,{suppliedStart:Timestamp.fromMillis(Date.now()+1800000)}));
  await assertFails(beginEarlyTrip(1800000,{suppliedStart:Timestamp.fromMillis(Date.now()-60000)}));
});

async function seedRecordedTrip(active=false) {
  await env.withSecurityRulesDisabled(async c => {
    const db=c.firestore(), start=Timestamp.fromMillis(Date.now()-7200000),end=Timestamp.fromMillis(Date.now()-3600000);
    await setDoc(doc(db,'groups/g/trips/recorded'),{userId:'borrower',driver:'Borrower',bookingId:'a',startAt:start,startKm:42000,
      endAt:active ? null : end,endKm:active ? null : 42030,status:active ? 'active' : 'completed',sync:'local',expenseId:'',remoteGroupId:'',payerId:'',borrowerId:''});
    await updateDoc(doc(db,'groups/g/bookings/a'),{status:active ? 'active':'completed'});
    await updateDoc(doc(db,'groups/g'),{activeTripId:active ? 'recorded':null,lastOdometer:42030});
  });
}
async function correction(user, action, extra={}) {
  const db=dbFor(user),ref=doc(db,'groups/g/trips/recorded'),g=doc(db,'groups/g'),b=doc(db,'groups/g/bookings/a');
  return runTransaction(db,async tx=>{
    const old=(await tx.get(ref)).data(), group=(await tx.get(g)).data();
    const id=`change-${action}-${old.changeId??'initial'}`;
    let patch={changeId:id,editedBy:user,editedByName:user,editedAt:serverTimestamp(),editReason:'Forgot to end the trip',...extra};
    if(action==='editTrip')patch={...patch,status:'completed',endAt:Timestamp.fromMillis(Date.now()-1800000),endKm:42035};
    if(action==='deleteTrip')patch={...patch,status:'deleted',deletedFrom:old.status};
    if(action==='restoreTrip')patch={...patch,status:old.deletedFrom};
    tx.set(doc(db,`groups/g/trips/recorded/changes/${id}`),{actorId:user,actorName:user,action,at:serverTimestamp(),reason:patch.editReason,before:old});
    tx.update(ref,patch);
    tx.update(b,{status:patch.status==='deleted'?'cancelled':patch.status});
    if(patch.status==='active')tx.update(g,{activeTripId:'recorded'});
    else if(group.activeTripId==='recorded')tx.update(g,{activeTripId:null,schedule:{},...(action==='editTrip'?{lastOdometer:42035}:{})});
  });
}
test('owner can correct a completed trip with an immutable history record',async()=>{
  await seedRecordedTrip();
  await assertSucceeds(correction('owner','editTrip'));
  const db=dbFor('owner');
  const t=(await getDoc(doc(db,'groups/g/trips/recorded'))).data();
  assert.equal(t.endKm,42035);assert.equal(t.editedBy,'owner');
  await assertFails(updateDoc(doc(db,`groups/g/trips/recorded/changes/${t.changeId}`),{reason:'rewritten'}));
});
test('owner can finish a forgotten active trip and release the car',async()=>{
  await seedRecordedTrip(true);await assertSucceeds(correction('owner','editTrip'));
  const g=(await getDoc(doc(dbFor('owner'),'groups/g'))).data();
  assert.equal(g.activeTripId,null);assert.equal(g.lastOdometer,42035);
});
test('owner can delete and restore a completed trip without losing readings',async()=>{
  await seedRecordedTrip();await assertSucceeds(correction('owner','deleteTrip'));
  let t=(await getDoc(doc(dbFor('owner'),'groups/g/trips/recorded'))).data();
  assert.equal(t.status,'deleted');assert.equal(t.endKm,42030);
  await assertSucceeds(correction('owner','restoreTrip'));
  t=(await getDoc(doc(dbFor('owner'),'groups/g/trips/recorded'))).data();assert.equal(t.status,'completed');
});
test('borrowers cannot correct or delete trips, even their own',async()=>{
  await seedRecordedTrip();await assertFails(correction('borrower','editTrip'));await assertFails(correction('borrower','deleteTrip'));
});
test('owner cannot correct readings without a history record or change the driver',async()=>{
  await seedRecordedTrip();const db=dbFor('owner');
  await assertFails(updateDoc(doc(db,'groups/g/trips/recorded'),{startKm:100}));
  await assertFails(correction('owner','editTrip',{userId:'owner'}));
});

test('owner can delete and restore an active trip but cannot replace another active trip',async()=>{
  await seedRecordedTrip(true);await assertSucceeds(correction('owner','deleteTrip'));
  assert.equal((await getDoc(doc(dbFor('owner'),'groups/g'))).data().activeTripId,null);
  await assertSucceeds(correction('owner','restoreTrip'));
  assert.equal((await getDoc(doc(dbFor('owner'),'groups/g'))).data().activeTripId,'recorded');
  await assertSucceeds(correction('owner','deleteTrip'));
  await env.withSecurityRulesDisabled(async c=>updateDoc(doc(c.firestore(),'groups/g'),{activeTripId:'another'}));
  await assertFails(correction('owner','restoreTrip'));
});
test('only owners can claim and complete a pending Spliit correction',async()=>{
  await seedRecordedTrip();
  await env.withSecurityRulesDisabled(async c=>updateDoc(doc(c.firestore(),'groups/g/trips/recorded'),{remoteGroupId:'remote',payerId:'payer',borrowerId:'alex',sync:'sent',expenseId:'remote-expense'}));
  await assertSucceeds(correction('owner','editTrip',{ledgerAction:'update',ledgerState:'pending',ledgerCreateStarted:false}));
  const ref=user=>doc(dbFor(user),'groups/g/trips/recorded');
  await assertFails(updateDoc(ref('borrower'),{ledgerState:'sending',ledgerClaimedAt:serverTimestamp()}));
  await assertFails(updateDoc(ref('borrower'),{sync:'sent',expenseId:'stale'}));
  await assertSucceeds(updateDoc(ref('owner'),{ledgerState:'sending',ledgerClaimedAt:serverTimestamp()}));
  await assertFails(correction('owner','deleteTrip'));
  await assertSucceeds(updateDoc(ref('owner'),{ledgerState:'done',sync:'sent',expenseId:'remote-expense'}));
});

function sharedRequest(ids=['borrower','sam']) {
  const at=Date.now()+3600000;
  return {userId:'borrower',driver:'Borrower',riderIds:ids,ownerClearances:{},
    startAt:Timestamp.fromMillis(at),endAt:Timestamp.fromMillis(at+7200000),estimatedKm:30,note:'Together',
    status:'requested',decisionNote:'',createdAt:serverTimestamp()};
}
async function seedExtraBorrowers(){
  await env.withSecurityRulesDisabled(async c=>{
    for(const id of ['sam','jo','pat','lee'])await setDoc(doc(c.firestore(),`groups/g/members/${id}`),{uid:id,name:id,role:'borrower',spliitMemberId:id});
  });
}
test('borrowers can request shared rides only with distinct household borrowers',async()=>{
  await seedExtraBorrowers();const db=dbFor('borrower');
  await assertSucceeds(setDoc(doc(db,'groups/g/bookings/shared'),sharedRequest()));
  await assertSucceeds(setDoc(doc(db,'groups/g/bookings/full'),sharedRequest(['borrower','sam','jo','pat','lee'])));
  for(const ids of [['borrower','stranger'],['borrower','owner'],['sam','borrower'],['borrower','sam','sam']]){
    await assertFails(setDoc(doc(db,'groups/g/bookings/bad'),sharedRequest(ids)));
  }
  await assertFails(setDoc(doc(db,'groups/g/bookings/prefilled'),{...sharedRequest(),ownerClearances:{owner:Timestamp.now()}}));
});
async function fineByMe(user,id='a') {
  const db=dbFor(user),ref=doc(db,`groups/g/bookings/${id}`),g=doc(db,'groups/g');
  return runTransaction(db,async tx=>{
    const group=(await tx.get(g)).data(),b=(await tx.get(ref)).data();
    if(b.status!=='requested')throw Error('already reviewed');
    const owners=(await getDocs(query(collection(db,'groups/g/members'),where('role','==','owner')))).docs.map(d=>d.id);
    const votes={...(b.ownerClearances??{}),[user]:serverTimestamp()};
    const approved=owners.every(o=>o in votes);
    const schedule={...group.schedule};
    if(approved){
      const start=b.startAt.toMillis(),end=b.endAt.toMillis();
      for(const [key,slot] of Object.entries(schedule))if(key!==id && start<slot.end && end>slot.start)throw Error('overlap');
      schedule[id]={start,end};
    }
    tx.update(ref,{[`ownerClearances.${user}`]:serverTimestamp(),status:approved?'approved':'requested'});
    tx.update(g,{schedule});
  });
}

test('Fine by me waits for all owners and concurrent votes are preserved',async()=>{
  await assertSucceeds(fineByMe('owner'));
  let b=(await getDoc(doc(dbFor('owner'),'groups/g/bookings/a'))).data();
  assert.equal(b.status,'requested');assert.deepEqual(Object.keys(b.ownerClearances),['owner']);
  assert.deepEqual((await getDoc(doc(dbFor('owner'),'groups/g'))).data().schedule,{});
  await assertSucceeds(fineByMe('owner2'));
  b=(await getDoc(doc(dbFor('owner'),'groups/g/bookings/a'))).data();assert.equal(b.status,'approved');
  await Promise.all([fineByMe('owner','b'),fineByMe('owner2','b')].map(async p=>{
    // b overlaps the now-approved a, so unanimous approval must be refused.
    try {await p;}catch(e){assert.match(e.message,/overlap/);}
  }));
  b=(await getDoc(doc(dbFor('owner'),'groups/g/bookings/b'))).data();assert.equal(b.status,'requested');
});
test('owners cannot record another owner response and borrowers cannot vote',async()=>{
  await assertFails(updateDoc(doc(dbFor('owner'),'groups/g/bookings/a'),{ownerClearances:{owner2:serverTimestamp()}}));
  await assertFails(updateDoc(doc(dbFor('borrower'),'groups/g/bookings/a'),{ownerClearances:{borrower:serverTimestamp()}}));
  await assertSucceeds(updateDoc(doc(dbFor('owner'),'groups/g/bookings/a'),{status:'approved'}));
});
test('concurrent Fine by me responses approve exactly once without losing votes',async()=>{
  await Promise.all([fineByMe('owner'),fineByMe('owner2')]);
  const db=dbFor('owner'),b=(await getDoc(doc(db,'groups/g/bookings/a'))).data();
  assert.equal(b.status,'approved');assert.deepEqual(Object.keys(b.ownerClearances).sort(),['owner','owner2']);
  assert.deepEqual(Object.keys((await getDoc(doc(db,'groups/g'))).data().schedule),['a']);
});
test('shared ride freezes all borrowers at start and only the requester starts',async()=>{
  await seedExtraBorrowers();
  await env.withSecurityRulesDisabled(async c=>updateDoc(doc(c.firestore(),'groups/g/bookings/a'),{riderIds:['borrower','sam'],status:'approved',startAt:Timestamp.fromMillis(Date.now()-60000)}));
  const start=(user,ids)=>{
    const db=dbFor(user),b=writeBatch(db);
    b.set(doc(db,'groups/g/trips/shared'),{userId:user,driver:user,bookingId:'a',riderIds:ids,borrowerIds:[],
      startAt:serverTimestamp(),startKm:42000,endAt:null,endKm:null,status:'active',sync:'local',expenseId:'',remoteGroupId:'',payerId:'',borrowerId:''});
    b.update(doc(db,'groups/g/bookings/a'),{status:'active'});b.update(doc(db,'groups/g'),{activeTripId:'shared'});return b.commit();
  };
  await assertFails(start('sam',['borrower','sam']));await assertFails(start('borrower',['borrower']));
  await assertSucceeds(start('borrower',['borrower','sam']));
});
test('Spliit shared expense cannot omit or substitute a rider mapping',async()=>{
  await seedExtraBorrowers();await seedRecordedTrip();
  await env.withSecurityRulesDisabled(async c=>{
    const db=c.firestore();await updateDoc(doc(db,'groups/g'),{spliitGroupId:'remote',ownerMemberId:'payer'});
    await updateDoc(doc(db,'groups/g/members/borrower'),{spliitMemberId:'alex'});
    await updateDoc(doc(db,'groups/g/trips/recorded'),{riderIds:['borrower','sam','jo','pat','lee'],borrowerIds:[]});
  });
  const ref=doc(dbFor('borrower'),'groups/g/trips/recorded');
  const patch=ids=>({sync:'sending',remoteGroupId:'remote',payerId:'payer',borrowerId:'alex',borrowerIds:ids});
  await assertFails(updateDoc(ref,patch(['alex'])));
  await assertFails(updateDoc(ref,patch(['alex','payer','jo','pat','lee'])));
  await assertFails(updateDoc(ref,patch(['alex','sam','sam','pat','lee'])));
  await assertSucceeds(updateDoc(ref,patch(['alex','sam','jo','pat','lee'])));
});
