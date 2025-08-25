# Ejercicio Simple DeFi Yield Farming

## Cómo usar Farms (Yield Farming) en PancakeSwap
📖 [Documentación oficial](https://docs.pancakeswap.finance/products/yield-farming/how-to-use-farms)

---

## Caso de uso
En este ejercicio, implementarás un proyecto **DeFi simple de Token Farm**.

La **Farm** debe permitir a los usuarios:
- Realizar depósitos y retiros de un token mock **LP**.
- Reclamar las recompensas generadas durante el staking.  
  Estas recompensas son tokens de la plataforma:  
  - **Nombre:** `DApp Token`  
  - **Token:** `DAPP`

El contrato contiene el marco y comentarios necesarios para implementarlo.  
Sigue los comentarios indicados para completarlo.

---

## Flujo del contrato `Simple Token Farm`

- Los usuarios depositan tokens LP con la función **`deposit()`**.
- Los usuarios reclaman recompensas con la función **`claimRewards()`**.
- Los usuarios pueden deshacer el staking con la función **`withdraw()`**, pero aún pueden reclamar las recompensas pendientes.
- Cada vez que se actualiza la cantidad de tokens LP en staking, las recompensas deben recalcularse primero.
- El propietario puede llamar a **`distributeRewardsAll()`** a intervalos regulares para actualizar las recompensas de todos los usuarios en staking.

---

## Contratos

- `LPToken.sol`: Contrato del token LP, utilizado para el staking.  
- `DappToken.sol`: Contrato del token de la plataforma, utilizado como recompensa.  
- `TokenFarm.sol`: Contrato principal de la Farm.  

---

## Requisitos

1. Crear un nuevo proyecto **Hardhat** e incluir el contrato proporcionado.  
2. Implementar todas las funciones, eventos y cualquier otro elemento mencionado en los comentarios del código.  
3. Desplegar los contratos en un entorno local.  

---

## Puntos Extra (Bonus)

### Bonus 1: Modifiers
Crear `modifier`s que validen:
- Si el llamador de la función es un usuario que está haciendo staking.  
- Si el llamador de la función es el **owner** del contrato.  

Añade los `modifier`s a las funciones que los requieran.  

---

### Bonus 2: Struct
Crear un `struct` que contenga la información de staking de un usuario y reemplazar los siguientes mappings:

```solidity
mapping(address => uint256) public stakingBalance;
mapping(address => uint256) public checkpoints;
mapping(address => uint256) public pendigRewards;
mapping(address => bool) public hasStaked;
mapping(address => bool) public isStaking;
```

## Bonus 3: Pruebas
Crea un archivo de pruebas para el contrato **Simple Token Farm** que permita verificar:

- Acuñar (**mint**) tokens LP para un usuario y realizar un depósito de esos tokens.
- Que la plataforma distribuya correctamente las recompensas a todos los usuarios en staking.
- Que un usuario pueda reclamar recompensas y verificar que se transfirieron correctamente a su cuenta.
- Que un usuario pueda deshacer el staking de todos los tokens LP depositados y reclamar recompensas pendientes, si las hay.

---

## Bonus 4: Recompensas variables por bloque
- Transforma las recompensas por bloque en un rango.
- Permite al propietario cambiar ese valor.

---

## Bonus 5: Comisión (fee) de retiro
- Cobra una comisión al momento de reclamar recompensas.
- Agrega una función para que el propietario pueda retirar esa comisión.

---

## Bonus 6: Proxy (nuevo proyecto)
Opciones:
1. Implementa el **Bonus 5** como una versión **V2** de nuestro contrato de farming.
2. Nuestra plataforma ha crecido y vamos a implementar farms para más tipos de tokens LP.
   - ¿Cómo podemos resolver el despliegue de nuevos contratos de farming ahorrando gas?

