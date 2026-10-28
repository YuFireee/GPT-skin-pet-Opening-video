// A successful explicit launch may precede creation of its first native window.
// This grace period never launches an application and cannot extend itself.
export function themeStartupPending(connection,deadline,now=Date.now()){
  return now<deadline&&(connection.owned===true||(connection.managedProcessCount>0&&connection.listenerCount===0));
}
