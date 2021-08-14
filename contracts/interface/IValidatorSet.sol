pragma solidity 0.6.4;

interface IValidatorSet {
  function misdemeanor(address validator) external;
  function felony(address validator)external;
}